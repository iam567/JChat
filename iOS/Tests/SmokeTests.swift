import Foundation
import AppKit

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw ChatError(message: "TEST FAILED: " + message) }
}

func readBody(_ request: URLRequest) throws -> [String: Any] {
    if let data = request.httpBody { return try JSONSerialization.jsonObject(with: data) as! [String: Any] }
    guard let stream = request.httpBodyStream else { throw ChatError(message: "Missing test request body") }
    stream.open(); defer { stream.close() }
    var bytes = [UInt8](repeating: 0, count: 4096), data = Data()
    while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(bytes, count: n) }
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

@main
struct SmokeTests {
    static func main() async throws {
        var speech = SpeechSegments()
        try expect(speech.append("明日は三時です。次の").count == 1, "speech splits at sentence punctuation")
        try expect(speech.append("会議に参加します。") == ["次の会議に参加します。"], "speech preserves text across recognition chunks")
        try expect(speech.flush() == nil, "flushing does not duplicate committed sentences")
        try expect(speech.append("価格は3.14円です").isEmpty, "decimal point is not a sentence boundary")
        try expect(speech.flush() == "価格は3.14円です", "pause or stop flushes trailing speech")
        let now = Date()
        try expect(VoiceSessionLimit.elapsed(since: now, now: now.addingTimeInterval(3599)) == 3599, "one hour session remains active before limit")
        try expect(VoiceSessionLimit.reached(since: now, now: now.addingTimeInterval(3600)), "one hour auto-stop boundary")
        try expect(VoiceSessionLimit.elapsed(since: now, now: now.addingTimeInterval(7200)) == 3600, "elapsed time is capped at 60 minutes")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = OpenAIClient(key: "test-key", model: "gpt-6.1-sol", session: URLSession(configuration: configuration))
        let payload = Translation(translation: "明天可以", summary: "礼貌确认", replies: [Reply(text: "明日で大丈夫です。", note: "自然礼貌")])
        let resultText = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        MockURLProtocol.handler = { request in
            let body = try readBody(request)
            try expect(body["store"] as? Bool == false, "provider storage disabled")
            try expect((body["instructions"] as? String)?.contains("日本語") == true, "target language used")
            try expect((body["instructions"] as? String)?.contains("中文") == true, "own language used")
            try expect((body["instructions"] as? String)?.contains("关系不明") == true, "auto tone handles uncertainty")
            try expect((body["input"] as? String)?.contains("対方の文脈") == true, "screenshot context included")
            let response: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": resultText]]]]]
            return (200, try JSONSerialization.data(withJSONObject: response))
        }
        let reply = try await client.translate(text: "明天可以", incoming: false, own: "zh", target: "ja", tone: "auto", context: "対方の文脈")
        try expect(reply.replies.first?.text == payload.replies.first?.text, "parse structured reply")
        MockURLProtocol.handler = { request in
            let body = try readBody(request)
            let input = body["input"] as! [[String: Any]]
            let contents = input[0]["content"] as! [[String: Any]]
            let urls = contents.filter { $0["type"] as? String == "input_image" }.compactMap { $0["image_url"] as? String }
            try expect(urls == ["data:image/jpeg;base64,first", "data:image/jpeg;base64,second"], "multiple screenshots keep user-confirmed order")
            try expect((body["instructions"] as? String)?.contains("右侧气泡是用户本人") == true, "screenshot roles distinguish self and other")
            let response: [String: Any] = ["status": "completed", "output": [["content": [["type": "output_text", "text": resultText]]]]]
            return (200, try JSONSerialization.data(withJSONObject: response))
        }
        _ = try await client.translate(text: "截图文字", incoming: true, own: "zh", target: "ja", tone: "auto", context: "", images: ["data:image/jpeg;base64,first", "data:image/jpeg;base64,second"])
        MockURLProtocol.handler = { request in
            let body = try readBody(request)
            try expect(body["text"] == nil, "live translation uses direct text without reply schema")
            try expect((body["instructions"] as? String)?.contains("翻译为中文") == true, "speech translates into own language")
            let response: [String: Any] = ["status": "completed", "output": [["content": [["type": "output_text", "text": "明天见。"]]]]]
            return (200, try JSONSerialization.data(withJSONObject: response))
        }
        let live = try await client.translateSpeech("また明日", own: "zh", source: "ja", context: "")
        try expect(live == "明天见。", "plain voice translation parsing")
        MockURLProtocol.handler = { _ in (401, Data("{}".utf8)) }
        do { try await client.verify(); throw ChatError(message: "Expected 401 failure") }
        catch let error as ChatError { try expect(error.message.contains("Key"), "actionable invalid key error") }
        MockURLProtocol.handler = { _ in (200, Data("{\"status\":\"incomplete\",\"output\":[]}".utf8)) }
        do { _ = try await client.translate(text: "你好", incoming: true, own: "ja", target: "zh", tone: "friend", context: ""); throw ChatError(message: "Expected incomplete failure") }
        catch let error as ChatError { try expect(error.message.contains("完整"), "incomplete response handled") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = folder.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = ChatSession(myLanguage: "zh", targetLanguage: "ja", turns: [Turn(kind: "incoming", original: "こんにちは", result: payload)])
        try HistoryStore.save([history], to: file)
        let restored = try HistoryStore.load(from: file)
        try expect(restored.first?.id == history.id, "history survives restart")
        try expect(restored.first?.turns.first?.original == "こんにちは", "history preserves original text")
        try expect(history.context.contains("对方消息") && !history.context.contains("用户想表达"), "pasted incoming text remains incoming context")
        var oldTurn = history.turns[0]
        oldTurn.original = "旧的错字原文"
        let corrected = Turn(kind: "incoming", original: "修正后的原文", result: payload, revises: oldTurn.id)
        let revisedHistory = ChatSession(myLanguage: "zh", targetLanguage: "ja", turns: [oldTurn, corrected])
        try expect(!revisedHistory.context.contains("旧的错字原文") && revisedHistory.context.contains("修正后的原文"), "corrected text replaces typo in future context")
        try HistoryStore.save([revisedHistory], to: file)
        let revisions = try HistoryStore.load(from: file)
        try expect(revisions[0].turns.count == 2 && revisions[0].turns[1].revises == oldTurn.id, "both versions and revision link persist")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldTurn)) as! [String: Any]
        legacy.removeValue(forKey: "revises")
        let legacyTurn = try JSONDecoder().decode(Turn.self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(legacyTurn.revises == nil && legacyTurn.original == oldTurn.original, "pre-edit history remains readable")
        try HistoryStore.save([], to: file)
        let deleted = try HistoryStore.load(from: file)
        try expect(deleted.isEmpty, "history deletion persists")
        // Generate an original Japanese fixture to exercise the actual local OCR engine.
        let image = NSImage(size: NSSize(width: 1100, height: 700))
        image.lockFocus()
        NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1100, height: 700)).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]
        ("明日の会議は午後三時からです。" as NSString).draw(at: NSPoint(x: 70, y: 500), withAttributes: attributes)
        ("資料を持ってきてください。" as NSString).draw(at: NSPoint(x: 70, y: 380), withAttributes: attributes)
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let recognized = try await ScreenshotReader.recognize(data)
        try expect(recognized.contains("会議") && recognized.contains("資料"), "Japanese screenshot OCR")
        print("PASS: structured response, language direction, automatic tone, context, API errors, history persistence/deletion, Japanese OCR, speech segmentation/hour limit, ordered screenshot input, live translation")
    }
}
