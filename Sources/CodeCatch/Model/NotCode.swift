import CodeCatchCore
import CryptoKit
import Foundation

/// A kind of message marked "Not a Code": none is read from it again. Kept in UserDefaults, so it
/// holds no message text: who sent it, for the list in Settings, and a hash of what the code was read from.
struct NotCodeRule: Codable, Equatable, Identifiable {
    /// `CodeItem.notCodeKey` of the message it was made from.
    let key: String
    let sender: String
    let added: Date
    var id: String { key }
}

extension CodeItem {
    /// What "Not a Code" remembers of a message: its sender (a mail sender by domain) and the lines the
    /// extractor read the code from (`CodeExtractor.Detection`), with every run of digits masked. The next
    /// order confirmation from the same shop reads the same; a code from it, introduced in other words,
    /// still comes through.
    static func notCodeKey(for detection: CodeExtractor.Detection, from message: IncomingMessage) -> String {
        let shape = detection.context.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        let sender =
            message.isMail
            ? ServiceIdentity.registrable(String(message.senderID.split(separator: "@").last ?? ""))
            : message.senderID.lowercased()
        return SHA256.hash(data: Data((sender + "\n" + shape).utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
