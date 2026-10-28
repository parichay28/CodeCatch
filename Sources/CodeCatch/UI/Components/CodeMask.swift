import Foundation

/// Hides the code inside a message but leaves the message readable.
enum CodeMask {
    /// The message with the code replaced by bullets, or nil when the code is not in it.
    static func masked(_ text: String, code: String) -> String? {
        guard let span = span(of: code, in: text) else { return nil }
        let bullets = text[span].map { $0.isNumber ? "•" : $0 }
        return String(text[..<span.lowerBound]) + String(bullets) + String(text[span.upperBound...])
    }

    /// Where the code sits in the text, separators included.
    static func span(of code: String, in text: String) -> Range<String.Index>? {
        let digits = Array(code.filter(\.isNumber))
        guard !digits.isEmpty else { return nil }
        var index = text.startIndex
        while index < text.endIndex {
            defer { index = text.index(after: index) }
            guard text[index].isNumber else { continue }
            // Not the tail of a longer number.
            if index > text.startIndex, text[text.index(before: index)].isNumber { continue }
            var cursor = index
            var matched = 0
            var end = index
            while cursor < text.endIndex, matched < digits.count {
                let character = text[cursor]
                if character.isNumber {
                    guard character == digits[matched] else { break }
                    matched += 1
                    end = text.index(after: cursor)
                } else if character == " " || character == "-" || character == "\u{00A0}" {
                    // A separator between digits: part of the hidden span.
                } else {
                    break
                }
                cursor = text.index(after: cursor)
            }
            if matched == digits.count, end == text.endIndex || !text[end].isNumber {
                return index..<end
            }
        }
        return nil
    }
}
