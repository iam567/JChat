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
        editingTurnID = nil; current = nil; draft = ""; incoming = false; pendingImage = nil; pendingText = nil
        tab = 0
    }

    func open(_ item: ChatSession) {
        guard !busy else { return }
        editingTurnID = nil; current = item; draft = ""; incoming = false; pendingImage = nil; pendingText = nil; tab = 0
    }

    func edit(_ turn: Turn) {
        guard !busy else { return }
        editingTurnID = turn.id
        draft = turn.original
        incoming = turn.kind != "outgoing"
        pendingText = nil; pendingImage = nil
    }

    func cancelEdit() {
        guard !busy else { return }
        editingTurnID = nil; draft = ""; incoming = false
        pendingText = nil; pendingImage = nil
    }

    var translationContext: String {
        guard var chat = current else { return "" }
        if let id = editingTurnID, let index = chat.turns.firstIndex(where: { $0.id == id }) {
            // Regeneration uses the conversation before the edited message.
            chat.turns = Array(chat.turns.prefix(index))
        }
        return chat.context
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
        pendingText = text; pendingIncoming = isIncoming; pendingImage = nil
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
        guard !busy else { return }
        editingTurnID = nil
        pendingImage = data; pendingText = nil; pendingIncoming = true
        busy = true; progress = "正在识别截图文字…"
        do {
            let text = try await ScreenshotReader.recognize(data)
            pendingText = text
            busy = false
            await translate(text: text, image: data, incoming: true, own: own, target: target, tone: tone, model: model)
        } catch { busy = false; self.error = error.localizedDescription }
    }

    func retry(own: String, target: String, tone: String, model: String) async {
        guard !busy else { return }
        if let text = pendingText {
            await translate(text: text, image: pendingImage, incoming: pendingIncoming, own: own, target: target, tone: tone, model: model)
        } else if let image = pendingImage {
            await screenshot(image, own: own, target: target, tone: tone, model: model)
        }
    }

    private func translate(text: String, image: Data?, incoming: Bool, own: String, target: String, tone: String, model: String) async {
        guard text.count <= 20000 else { error = "文字过长，请分段翻译"; return }
        busy = true; progress = incoming ? "正在翻译对方的意思…" : "正在结合对话生成回复…"
        do {
            let result = try await OpenAIClient(key: KeyStore.read(), model: model).translate(text: text, incoming: incoming, own: own, target: target, tone: tone, context: translationContext)
            var thumbnail: Data?
            if let image, let uiImage = UIImage(data: image) {
                let size = uiImage.size
                let scale = min(1, 700 / max(size.width, size.height))
                let renderSize = CGSize(width: size.width * scale, height: size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: renderSize)
                thumbnail = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: renderSize)) }.jpegData(compressionQuality: 0.7)
            }
            append(Turn(kind: image != nil ? "screenshot" : (incoming ? "incoming" : "outgoing"), original: text, result: result, thumbnail: thumbnail, revises: editingTurnID), own: own, target: target)
            if image == nil, draft == text { draft = "" }
            if incoming { self.incoming = false }
            editingTurnID = nil
            pendingText = nil; pendingImage = nil
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}
