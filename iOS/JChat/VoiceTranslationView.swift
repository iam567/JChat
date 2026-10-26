import SwiftUI

@available(iOS 26.0, *)
struct VoiceTranslationView: View {
    @StateObject private var voice = VoiceTranslator()
    @Environment(\.scenePhase) private var phase
    @AppStorage("myLanguage") private var own = "zh"
    @AppStorage("targetLanguage") private var source = "ja"
    @AppStorage("openAIModel") private var model = "gpt-6.1-sol"
    @State private var startTask: Task<Void, Never>?
    let saveHistory: (ChatSession) -> Void
    private var clock: String { String(format: "%02d:%02d / 60:00", voice.elapsed / 60, voice.elapsed % 60) }
    private var active: Bool { voice.listening || voice.preparing || voice.finishing }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("对方说", selection: $source) {
                        ForEach(AppLanguage.all) { Text($0.name).tag($0.id) }
                    }.pickerStyle(.menu)
                    Image(systemName: "arrow.right")
                    Text(AppLanguage.name(own)).fontWeight(.semibold)
                    Spacer()
                    Text(clock).monospacedDigit().font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal).disabled(!voice.canStart)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(voice.lines) { line in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(line.original).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                                    if let text = line.translation {
                                        Text(text).font(.title3).lineSpacing(4).textSelection(.enabled)
                                        Button { UIPasteboard.general.string = text } label: { Label("复制译文", systemImage: "doc.on.doc").font(.caption) }
                                    } else if let error = line.error {
                                        Text(error).font(.caption).foregroundStyle(.red)
                                        Button("重试这一句") { voice.retry(line.id) }.font(.caption)
                                    } else {
                                        HStack { ProgressView(); Text(line.translating ? "正在翻译…" : "等待翻译…").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                                    .id(line.id)
                            }
                            if !voice.liveText.isEmpty {
                                VStack(alignment: .leading, spacing: 7) {
                                    Label("正在识别…", systemImage: "waveform").font(.caption).foregroundStyle(.secondary)
                                    Text(voice.liveText).font(.body).textSelection(.enabled)
                                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("voiceBottom")
                        }.padding()
                    }
                    .onChange(of: voice.lines.count) { _, _ in withAnimation { proxy.scrollTo("voiceBottom", anchor: .bottom) } }
                    .onChange(of: voice.liveText) { _, _ in proxy.scrollTo("voiceBottom", anchor: .bottom) }
                }
                VStack(spacing: 10) {
                    if !voice.status.isEmpty { Text(voice.status).font(.caption).foregroundStyle(.secondary) }
                    if voice.pendingCount > 0 { Text("还有 \(voice.pendingCount) 句正在处理").font(.caption2).foregroundStyle(.secondary) }
                    Button {
                        if voice.preparing { startTask?.cancel(); voice.cancelPreparation() }
                        else if voice.listening { Task { await voice.stop() } }
                        else {
                            voice.saveHistory = saveHistory
                            startTask = Task { await voice.start(own: own, source: source, model: model) }
                        }
                    } label: {
                        Label(voice.preparing ? "取消准备" : (voice.listening ? "停止收音" : (voice.finishing ? "正在收尾…" : "开始语音翻译")), systemImage: voice.listening ? "stop.circle.fill" : "mic.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(17)
                    }.buttonStyle(.borderedProminent)
                        .tint(voice.listening ? .red : .accentColor)
                        .disabled(voice.finishing || (!active && !voice.canStart))
                    Text("收音时屏幕保持常亮 · 单次最长 60 分钟").font(.caption2).foregroundStyle(.secondary)
                }.padding().background(Color(uiColor: .systemBackground))
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("语音翻译").navigationBarTitleDisplayMode(.inline)
            .alert("语音翻译", isPresented: Binding(get: { voice.error != nil }, set: { if !$0 { voice.error = nil } })) {
                Button("知道了", role: .cancel) { voice.error = nil }
            } message: { Text(voice.error ?? "") }
        }
        .onDisappear {
            startTask?.cancel()
            if voice.preparing { voice.cancelPreparation() }
            if voice.listening { Task { await voice.stop() } }
        }
        .onChange(of: phase) { _, value in
            if value == .background {
                if voice.preparing { startTask?.cancel(); voice.cancelPreparation() }
                if voice.listening { Task { await voice.stop() } }
            }
        }
    }
}
