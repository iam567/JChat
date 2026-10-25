import SwiftUI
import UIKit

@MainActor
final class ChatModel: ObservableObject {
    private var historyReadable = true
    @Published var histories: [ChatSession] = []
    @Published var current: ChatSession?
    @Published var busy = false
    @Published var progress = ""
    @Published var error: String?
    @Published var draft = ""
    @Published var editingTurnID: UUID?
    @Published var incoming = false
    @Published var tab = 0
    @Published var pendingImages: [Data] = []
    @Published var pendingImage: Data?
    @Published var pendingText: String?
    @Published var pendingIncoming = false

    init() {
        do { histories = try HistoryStore.load() }
        catch { historyReadable = false; self.error = "历史记录读取失败，原文件已保留。请不要清空历史。" }
    }

    func persist() {
        guard historyReadable else { error = "历史文件无法读取，新内容暂时不能保存，请先保留原文件以便恢复"; return }
        do { try HistoryStore.save(histories) }
        catch { self.error = "历史记录未能保存，请检查手机剩余空间后重试" }
    }

    func startNew() {
        guard !busy else { return }
        editingTurnID = nil; current = nil; draft = ""; incoming = false; pendingImage = nil; pendingImages = []; pendingText = nil
        tab = 0
    }

    func open(_ item: ChatSession) {
        guard !busy else { return }
        editingTurnID = nil; current = item; draft = ""; incoming = false; pendingImage = nil; pendingImages = []; pendingText = nil; tab = 0
    }

    func edit(_ turn: Turn) {
        guard !busy else { return }
        editingTurnID = turn.id
        draft = turn.original
        incoming = turn.kind != "outgoing"
        pendingText = nil; pendingImage = nil; pendingImages = []
    }

    func cancelEdit() {
        guard !busy else { return }
        editingTurnID = nil; draft = ""; incoming = false
        pendingText = nil; pendingImage = nil; pendingImages = []
    }

    var translationContext: String {
        guard var chat = current else { return "" }
        if let id = editingTurnID, let index = chat.turns.firstIndex(where: { $0.id == id }) {
            // Regeneration uses the conversation before the edited message.
            chat.turns = Array(chat.turns.prefix(index))
        }
        return chat.context
    }

    func saveVoiceHistory(_ session: ChatSession) {
        guard !session.turns.isEmpty else { return }
        histories.removeAll { $0.id == session.id }
        histories.insert(session, at: 0)
        persist()
    }

    func remove(_ ids: Set<UUID>) {
        histories.removeAll { ids.contains($0.id) }
        if let current, ids.contains(current.id) { startNew() }
        persist()
    }

    func append(_ turn: Turn, own: String, target: String) {
        var chat = current ?? ChatSession(myLanguage: own, targetLanguage: target)
        chat.turns.append(turn)
        chat.myLanguage = own; chat.targetLanguage = target
        current = chat
        histories.removeAll { $0.id == chat.id }
        histories.insert(chat, at: 0)
        persist()
    }

    func send(own: String, target: String, tone: String, model: String) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return }
        let isIncoming = incoming
        pendingText = text; pendingIncoming = isIncoming; pendingImage = nil; pendingImages = []
        await translate(text: text, image: nil, incoming: isIncoming, own: own, target: target, tone: tone, model: model)
    }

    func latest(own: String, target: String, tone: String, model: String) async {
        guard !busy else { return }
        busy = true; progress = "正在读取最新截图…"
        do {
            let data = try await ScreenshotReader.latest()
            busy = false
            await screenshot(data, own: own, target: target, tone: tone, model: model)
        } catch { busy = false; self.error = error.localizedDescription }
    }

    func screenshot(_ data: Data, own: String, target: String, tone: String, model: String) async {
        await screenshots([data], own: own, target: target, tone: tone, model: model)
    }

    func screenshots(_ images: [Data], own: String, target: String, tone: String, model: String) async {
        guard !busy, !images.isEmpty else { return }
        editingTurnID = nil
        pendingImages = images; pendingImage = images.first; pendingText = nil; pendingIncoming = true
        busy = true
        do {
            var texts: [String] = []
            for (index, data) in images.enumerated() {
                progress = "正在识别第\(index + 1)/\(images.count)张截图…"
                // The original images still provide bubble geometry when OCR misses a line.
                let text = (try? await ScreenshotReader.recognize(data)) ?? "（文字识别不完整，请结合原图阅读）"
                texts.append("【第\(index + 1)张截图】\n" + text)
            }
            let text = texts.joined(separator: "\n\n")
            pendingText = text; busy = false
            await translate(text: text, image: images.first, incoming: true, own: own, target: target, tone: tone, model: model)
        }
    }

    func retry(own: String, target: String, tone: String, model: String) async {
        guard !busy else { return }
        if let text = pendingText {
            await translate(text: text, image: pendingImage, incoming: pendingIncoming, own: own, target: target, tone: tone, model: model)
        } else if let image = pendingImage {
            await screenshot(image, own: own, target: target, tone: tone, model: model)
        }
    }

    private func imageData(_ data: Data, maximum: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maximum / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: quality)
    }

    private func translate(text: String, image: Data?, incoming: Bool, own: String, target: String, tone: String, model: String) async {
        guard text.count <= 20000 else { error = "文字过长，请分段翻译"; return }
        busy = true; progress = incoming ? "正在翻译对方的意思…" : "正在结合对话生成回复…"
        do {
            let sourceImages = image == nil ? [] : (pendingImages.isEmpty ? [image!] : pendingImages)
            let encoded = sourceImages.compactMap { imageData($0, maximum: 2800, quality: 0.82) }
            guard encoded.count == sourceImages.count else { throw ChatError(message: "图片无法读取，请重新选择") }
            let imageURLs = encoded.map { "data:image/jpeg;base64," + $0.base64EncodedString() }
            let result = try await OpenAIClient(key: KeyStore.read(), model: model).translate(text: text, incoming: incoming, own: own, target: target, tone: tone, context: translationContext, images: imageURLs)
            let thumbs = sourceImages.compactMap { imageData($0, maximum: 700, quality: 0.7) }
            append(Turn(kind: image != nil ? "screenshot" : (incoming ? "incoming" : "outgoing"), original: text, result: result, thumbnail: thumbs.first, revises: editingTurnID, thumbnails: thumbs.count > 1 ? thumbs : nil), own: own, target: target)
            if image == nil, draft == text { draft = "" }
            if incoming { self.incoming = false }
            editingTurnID = nil
            pendingText = nil; pendingImage = nil; pendingImages = []
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}
