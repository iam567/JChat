import SwiftUI
import Speech
import AVFoundation

@available(iOS 26.0, *)
private final class AudioBridge: @unchecked Sendable {
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    let converter: AVAudioConverter
    let outputFormat: AVAudioFormat
    init(input: AVAudioFormat, output: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        guard let converter = AVAudioConverter(from: input, to: output) else { throw ChatError(message: "无法转换麦克风音频格式") }
        self.converter = converter; self.outputFormat = output; self.continuation = continuation
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate)) + 256
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return buffer
        }
        if error == nil, status != .error, output.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: output)) }
    }
}

struct VoiceLine: Identifiable {
    let id = UUID()
    let createdAt = Date()
    let original: String
    var translation: String?
    var error: String?
    var translating = false
}

@available(iOS 26.0, *)
@MainActor
final class VoiceTranslator: ObservableObject {
    @Published var listening = false
    @Published var preparing = false
    @Published var finishing = false
    @Published var elapsed = 0
    @Published var status = ""
    @Published var liveText = ""
    @Published var lines: [VoiceLine] = []
    @Published var error: String?
    private var tapInstalled = false
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var translationTasks: [UUID: Task<Void, Never>] = [:]
    private var segmenter = SpeechSegments()
    private var finalRanges: Set<String> = []
    private var latestFinal = Date()
    private var partialText = ""
    private var partialUpdatedAt = Date()
    private var lastForcedFinal = Date()
    private var startedAt: Date?
    private var priorIdleDisabled = false
    private var idleOwned = false
    private var observers: [NSObjectProtocol] = []
    private var own = "zh", source = "ja", model = "gpt-6.1-sol", key = ""
    private var voiceHistory: ChatSession?
    var saveHistory: ((ChatSession) -> Void)?
    private var generation = UUID()
    var pendingCount: Int { lines.filter { $0.translation == nil && $0.error == nil }.count }
    var canStart: Bool { !preparing && !listening && !finishing && translationTasks.isEmpty && pendingCount == 0 }

    func start(own: String, source: String, model: String) async {
        guard canStart else { return }
        key = KeyStore.read()
        guard !key.isEmpty else { error = "请先在直接翻译的设置里填写 OpenAI API Key"; return }
        self.own = own; self.source = source; self.model = model
        preparing = true; status = "正在准备语音识别…"
        priorIdleDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true; idleOwned = true
        generation = UUID(); let token = generation
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw ChatError(message: "请在系统设置中允许 JChat 使用麦克风") }
            let authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard authorization == .authorized else { throw ChatError(message: "请在系统设置中允许 JChat 使用语音识别") }
            guard SpeechTranscriber.isAvailable else { throw ChatError(message: "这台设备暂不支持持续语音识别，请在真机上使用") }
            let localeIDs = ["zh": "zh-CN", "ja": "ja-JP", "en": "en-US", "ko": "ko-KR", "fr": "fr-FR", "de": "de-DE", "es": "es-ES"]
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIDs[source] ?? source)) else { throw ChatError(message: "系统暂不支持所选语音语言，请更换语言") }
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                status = "首次使用，正在下载所需语音识别模型…"
                try await installation.downloadAndInstall()
            }
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try audioSession.setActive(true)
            let engine = AVAudioEngine()
            self.engine = engine
            let input = engine.inputNode.outputFormat(forBus: 0)
            guard input.sampleRate > 0, input.channelCount > 0,
                  let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: input) else { throw ChatError(message: "麦克风暂时不可用，请检查连接") }
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            try await analyzer.prepareToAnalyze(in: format)
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
            self.continuation = continuation
            let bridge = try AudioBridge(input: input, output: format, continuation: continuation)
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: input) { buffer, _ in bridge.append(buffer) }
            tapInstalled = true
            segmenter = SpeechSegments(); finalRanges = []; partialText = ""; liveText = ""; lines = []; elapsed = 0
            voiceHistory = ChatSession(myLanguage: own, targetLanguage: source)
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, token == self.generation else { return }
                        self.receive(text: String(result.text.characters), final: result.isFinal,
                                     rangeID: "\(result.range.start.seconds):\(result.range.duration.seconds)")
                    }
                } catch {
                    guard let self, token == self.generation, self.listening else { return }
                    self.error = "语音识别中断：\(error.localizedDescription)"
                    Task { await self.stop() }
                }
            }
            try await analyzer.start(inputSequence: stream)
            engine.prepare(); try engine.start()
            guard token == generation else { throw CancellationError() }
            startedAt = Date(); latestFinal = Date(); partialUpdatedAt = Date(); lastForcedFinal = Date()
            listening = true; preparing = false; status = "正在听…识别到句子后自动翻译"
            observers = [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    if name == AVAudioSession.routeChangeNotification,
                       let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                       raw != AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { return }
                    if name == AVAudioSession.interruptionNotification,
                       let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                       raw != AVAudioSession.InterruptionType.began.rawValue { return }
                    Task { @MainActor in
                        guard let self, self.listening else { return }
                        self.status = "收音已中断，已保留翻译内容"
                        await self.stop()
                    }
                }
            }
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self, self.listening else { return }
                    self.elapsed = VoiceSessionLimit.elapsed(since: self.startedAt ?? Date(), now: Date())
                    if !self.partialText.isEmpty, Date().timeIntervalSince(self.lastForcedFinal) >= 1.2,
                       Date().timeIntervalSince(self.partialUpdatedAt) >= 1.0 || (Date().timeIntervalSince(self.lastForcedFinal) >= 5 && self.partialText.count >= 60) {
                        self.lastForcedFinal = Date()
                        try? await self.analyzer?.finalize(through: nil)
                    }
                    if Date().timeIntervalSince(self.latestFinal) >= 1.2, let sentence = self.segmenter.flush() { self.enqueue(sentence) }
                    if self.elapsed >= 3600 { self.status = "已满 60 分钟，收音已停止"; await self.stop(); return }
                }
            }
        } catch {
            guard token == generation else { return }
            preparing = false
            cleanupAudio()
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }

    private func receive(text: String, final: Bool, rangeID: String) {
        if final {
            guard finalRanges.insert(rangeID).inserted else { return }
            latestFinal = Date(); partialText = ""
            for sentence in segmenter.append(text) { enqueue(sentence) }
        } else {
            if partialText != text { partialUpdatedAt = Date() }
            partialText = text
        }
        liveText = segmenter.pending + partialText
    }

    private func enqueue(_ text: String) {
        lines.append(VoiceLine(original: text))
        drain()
        if pendingCount > 24, listening {
            status = "网络翻译暂时跟不上，已暂停收音，正在处理已识别内容"
            Task { await stop() }
        }
    }

    private func drain() {
        for index in lines.indices where translationTasks.count < 3 && lines[index].translation == nil && lines[index].error == nil && !lines[index].translating {
            let id = lines[index].id, text = lines[index].original, token = generation
            let context = lines[..<index].suffix(3).map(\.original).joined(separator: "\n")
            lines[index].translating = true
            translationTasks[id] = Task { [weak self] in
                guard let self else { return }
                do {
                    let translated = try await OpenAIClient(key: self.key, model: self.model).translateSpeech(text, own: self.own, source: self.source, context: context)
                    guard token == self.generation, let position = self.lines.firstIndex(where: { $0.id == id }) else { return }
                    self.lines[position].translation = translated
                } catch {
                    guard token == self.generation, let position = self.lines.firstIndex(where: { $0.id == id }) else { return }
                    self.lines[position].error = error.localizedDescription
                }
                self.translationTasks[id] = nil
                if let position = self.lines.firstIndex(where: { $0.id == id }) { self.lines[position].translating = false }
                self.persistHistory(); self.drain()
            }
        }
    }

    func retry(_ id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }), !lines[index].translating else { return }
        lines[index].error = nil
        drain()
    }

    private func persistHistory() {
        guard var history = voiceHistory else { return }
        history.turns = lines.map { line in
            Turn(id: line.id, createdAt: line.createdAt, kind: "incoming", original: line.original,
                 result: Translation(translation: line.translation ?? "（尚未完成翻译，可复制原文重新翻译）", summary: "", replies: []))
        }
        voiceHistory = history
        saveHistory?(history)
    }

    func stop() async {
        guard listening || preparing else { return }
        listening = false; preparing = false; finishing = true
        timerTask?.cancel(); timerTask = nil
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if idleOwned { UIApplication.shared.isIdleTimerDisabled = priorIdleDisabled; idleOwned = false }
        continuation?.finish(); continuation = nil
        if let analyzer { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        // The results sequence finishes after delivering final words.
        await resultsTask?.value
        resultsTask = nil
        if !partialText.isEmpty {
            for sentence in segmenter.append(partialText) { enqueue(sentence) }
            partialText = ""
        }
        if let remainder = segmenter.flush() { enqueue(remainder) }
        liveText = ""
        cleanupAudio(); finishing = false
        persistHistory()
        if status.hasPrefix("正在") { status = "收音已停止" }
    }

    func cancelPreparation() {
        guard preparing else { return }
        generation = UUID(); preparing = false; cleanupAudio()
    }

    private func cleanupAudio() {
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine = nil; continuation?.finish(); continuation = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        if idleOwned { UIApplication.shared.isIdleTimerDisabled = priorIdleDisabled; idleOwned = false }
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
