import Foundation

/// Buffers only finalized recognition text; provisional revisions never become duplicate translations.
struct SpeechSegments {
    private(set) var pending = ""
    mutating func append(_ text: String) -> [String] {
        if let last = pending.last, let first = text.first,
           last.isASCII && last.isLetter && first.isASCII && first.isLetter { pending += " " }
        pending += text
        var ready: [String] = []
        while let end = boundary() {
            let sentence = String(pending[...end]).trimmingCharacters(in: .whitespacesAndNewlines)
            pending = String(pending[pending.index(after: end)...])
            if !sentence.isEmpty { ready.append(sentence) }
        }
        return ready
    }
    mutating func flush() -> String? {
        let text = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        return text.isEmpty ? nil : text
    }
    private func boundary() -> String.Index? {
        var count = 0
        for index in pending.indices {
            count += 1
            let char = pending[index]
            if "。！？!?\n".contains(char) { return index }
            if char == "." {
                let before = index > pending.startIndex ? pending[pending.index(before: index)] : " "
                let nextIndex = pending.index(after: index)
                let after = nextIndex < pending.endIndex ? pending[nextIndex] : " "
                if !(before.isNumber && after.isNumber) && (after.isWhitespace || nextIndex == pending.endIndex) { return index }
            }
            if count >= 90 && "、，,；; ".contains(char) { return index }
            if count >= 180 { return index }
        }
        return nil
    }
}


enum VoiceSessionLimit {
    static let seconds = 3600
    static func elapsed(since start: Date, now: Date) -> Int {
        min(seconds, max(0, Int(now.timeIntervalSince(start))))
    }
    static func reached(since start: Date, now: Date) -> Bool {
        now.timeIntervalSince(start) >= Double(seconds)
    }
}
