import CodeCatchCore
import Foundation
import SQLite3

/// ~/Library/Messages/chat.db: incoming iMessages and forwarded SMS.
final class MessagesStore: LocalStore {
    static let dbPath = NSHomeDirectory() + "/Library/Messages/chat.db"
    static let sourceKey = "messages"

    let name = "Messages"
    private(set) var position: Int64 = 0
    private var db: SQLiteReader?
    private let path: String
    /// The message at `position`, and where an earlier watcher stopped reading.
    private var guid: String?
    private let resume: (row: Int64, guid: String)?

    init(path: String = MessagesStore.dbPath, after position: ReadPosition? = nil) {
        self.path = path
        if case .row(let row, let guid) = position { resume = (row, guid) } else { resume = nil }
    }

    var readPosition: ReadPosition? { guid.map { .row(position, guid: $0) } }

    /// Starts at the last ROWID before `since`, or where an earlier watcher stopped when that is later.
    func open(since: Date) -> String? {
        guard let db = SQLiteReader(path: path),
            let start = try? db.query(
                "SELECT COALESCE(MAX(ROWID), 0) FROM message WHERE date < ?1",
                Int64(since.timeIntervalSinceReferenceDate * 1e9), row: { sqlite3_column_int64($0, 0) }
            ).first
        else { return SourceStatus.needsDiskAccess }
        self.db = db
        // Only while that row is still the same message: a rebuilt or replaced database numbers its rows anew.
        if let resume, resume.row > start, Self.guid(at: resume.row, in: db) == resume.guid {
            (position, guid) = resume
        } else {
            (position, guid) = (start, Self.guid(at: start, in: db))
        }
        return nil
    }

    private static func guid(at row: Int64, in db: SQLiteReader) -> String? {
        (try? db.query("SELECT guid FROM message WHERE ROWID = ?1", row) { s in sqlite3_column_text(s, 0).map { String(cString: $0) } })?.first ?? nil
    }

    func close() { db = nil }

    func newMessages() throws -> [IncomingMessage] {
        guard let db else { return [] }
        let sql = """
            SELECT m.ROWID, m.text, m.attributedBody, m.date, COALESCE(h.id, ''), m.is_from_me, m.guid
            FROM message m LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE m.ROWID > ?1 ORDER BY m.ROWID LIMIT 200
            """
        return try db.query(sql, position) { s -> IncomingMessage? in
            position = sqlite3_column_int64(s, 0)
            guid = sqlite3_column_text(s, 6).map { String(cString: $0) }
            guard sqlite3_column_int(s, 5) == 0 else { return nil }
            var text = sqlite3_column_text(s, 1).map { String(cString: $0) } ?? ""
            if text.isEmpty, let blob = sqlite3_column_blob(s, 2) {
                text = TypedStream.text(fromAttributedBody: Data(bytes: blob, count: Int(sqlite3_column_bytes(s, 2)))) ?? ""
            }
            guard !text.isEmpty else { return nil }
            let raw = sqlite3_column_int64(s, 3)
            let date = Date(timeIntervalSinceReferenceDate: raw > 1_000_000_000_000 ? Double(raw) / 1e9 : Double(raw))
            let handle = String(cString: sqlite3_column_text(s, 4))
            return IncomingMessage(
                text: text, subject: nil, senderName: "", senderID: handle,
                sourceKey: Self.sourceKey, sourceLabel: name, date: date, isMail: false,
                messageID: String(position))
        }.compactMap { $0 }
    }
}
