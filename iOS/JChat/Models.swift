import Foundation

struct AppLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    static let all = [AppLanguage(id: "zh", name: "中文"), .init(id: "ja", name: "日本語"), .init(id: "en", name: "English"), .init(id: "ko", name: "한국어"), .init(id: "fr", name: "Français"), .init(id: "de", name: "Deutsch"), .init(id: "es", name: "Español")]
    static func name(_ id: String) -> String { all.first { $0.id == id }?.name ?? id }
}

struct Tone: Identifiable {
    let id: String
    let name: String
    let prompt: String
    static let all: [Tone] = [
        .init(id: "auto", name: "✨ AI 自动判断", prompt: "结合对方的措辞、敬语、对话背景和可合理推断的关系，选择合适的回复语气。对方客气时保持客气；对方若为上级、客户或前辈，即使对方用指令语气也礼貌稳妥回复；朋友之间则自然轻松。关系不明时采用自然、礼貌的中性语气，不把推测当事实，不机械模仿粗鲁或命令。"),
        .init(id: "boss", name: "🫡 上级尊敬", prompt: "对上级、客户或前辈使用礼貌、尊重的敬语，谦逊、稳妥。"),
        .init(id: "friend", name: "😊 朋友轻松", prompt: "自然轻松的朋友语气，亲切，不生硬。"),
        .init(id: "subordinate", name: "📣 下级命令", prompt: "以对下级明确下达指示的口吻表达，直接、简洁、有力，避免客气请求，但不要脏话或人格攻击。"),
        .init(id: "flirty", name: "😏 泡妞调情", prompt: "暧昧、轻松、温柔、有趣，有一点调情感，避免油腻或过度直白。"),
        .init(id: "thug", name: "😎 地痞流氓", prompt: "街头、强势、短促、有压迫感，可以不客气，但不要具体暴力威胁、违法指令或人格羞辱。"),
        .init(id: "eq", name: "🤝 高情商优化", prompt: "圆滑、体面、委婉、成熟，让人舒服，同时保留真实意图。")
    ]
}

struct Reply: Codable, Identifiable {
    var text: String
    var note: String
    var id: String { text + note }
}

struct Translation: Codable {
    var translation: String
    var summary: String
    var replies: [Reply]
}

struct Turn: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var kind: String
    var original: String
    var result: Translation
    var thumbnail: Data?
    var revises: UUID? = nil
    var thumbnails: [Data]? = nil
    var generatedSuggestion: Bool? = nil
}

struct ChatSession: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var myLanguage: String
    var targetLanguage: String
    var turns: [Turn] = []
    var title: String {
        let text = turns.first.map { $0.kind == "screenshot" ? $0.result.summary : $0.original } ?? "新对话"
        return String(text.replacingOccurrences(of: "\n", with: " ").prefix(42))
    }
    var context: String {
        let superseded = Set(turns.compactMap(\.revises))
        return String(turns.filter { !superseded.contains($0.id) }.suffix(6).map { turn in
            if turn.kind != "outgoing" { return "对方消息或截图识别资料：\(turn.original)\n翻译和解读：\(turn.result.translation)\n\(turn.result.summary)" }
            if turn.generatedSuggestion == true { return "AI建议候选（用户尚未选择或发送，不代表用户真实立场）：\(turn.result.replies.map(\.text).joined(separator: " / "))" }
            return "用户想表达：\(turn.original)\n回复候选（不代表已经发送）：\(turn.result.replies.map(\.text).joined(separator: " / "))"
        }.joined(separator: "\n\n").suffix(24000))
    }
}

enum HistoryStore {
    static var url: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JChat", isDirectory: true)
        return directory.appendingPathComponent("history.json")
    }
    static func load(from fileURL: URL = HistoryStore.url) throws -> [ChatSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([ChatSession].self, from: Data(contentsOf: fileURL))
    }
    static func save(_ sessions: [ChatSession], to fileURL: URL = HistoryStore.url) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(sessions).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
