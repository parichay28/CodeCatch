import Foundation
import Network

protocol MailConnection: Sendable {
    var capabilities: Set<String> { get async }
    func openInbox(_ account: MailAccount) async throws -> [IMAPConnection.Response]
    func search(_ criteria: String) async throws -> [Int]
    func fetch(_ uids: [Int], account: MailAccount) async throws -> [IncomingMessage]
    func idle(renewAfter: TimeInterval) async throws
    func command(_ cmd: String, timeout: TimeInterval) async throws -> [IMAPConnection.Response]
    func close() async
}

extension IMAPConnection: MailConnection {}

enum MailWatcher {
    /// A fresh start reads at most the newest this many: after a long gap only those can still hold a
    /// live code. Carrying on after sleep reads no more than that either.
    static let backfill = 60

    /// Watches one INBOX until cancelled: backfills history, or carries on from `position`, then IDLEs,
    /// reconnecting with backoff.
    static func watch(
        _ account: MailAccount,
        from position: ReadPosition? = nil,
        status: @escaping @MainActor (SourceStatus) -> Void,
        deliver: @escaping @MainActor (IncomingMessage) -> Void,
        event: @escaping @MainActor (SourceEvent) -> Void = { _ in },
        lookback: TimeInterval = 7 * 86400,
        connection: (@Sendable () -> any MailConnection)? = nil,
        retryDelay: TimeInterval = 5
    ) async {
        var (lastUID, uidValidity): (Int?, Int?) = if case .uid(let uid, let validity) = position { (uid, validity) } else { (nil, nil) }
        var resuming = lastUID != nil
        var backoff = retryDelay
        while !Task.isCancelled {
            let conn: any MailConnection
            do { conn = try connection?() ?? IMAPConnection(account: account) } catch {
                await status(.failed(describe(error)))
                return
            }
            do {
                try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    await event(.retry(nil))
                    await status(.connecting)
                    let examine = try await conn.openInbox(account)
                    try Task.checkCancellation()
                    let validity = examine.lazy.compactMap { $0.number(after: "UIDVALIDITY ") }.first
                    if validity != uidValidity { lastUID = nil }
                    uidValidity = validity

                    func receive(_ uids: [Int]) async throws {
                        try Task.checkCancellation()
                        try await hand(try await conn.fetch(uids, account: account), event: event, deliver: deliver)
                    }
                    func commit(_ uid: Int) async {
                        lastUID = uid
                        await event(.read(.uid(uid, validity: uidValidity)))
                    }

                    if lastUID == nil {
                        let recent = try await conn.search("SINCE \(imapDay(Date().addingTimeInterval(-lookback)))")
                        let next = examine.lazy.compactMap { $0.number(after: "UIDNEXT ") }.first
                        try await receive(Array(recent.suffix(backfill)))
                        await commit(max((next ?? 1) - 1, recent.max() ?? 0))
                        resuming = false
                    }
                    try Task.checkCancellation()
                    await status(.live)
                    backoff = retryDelay
                    let canIdle = await conn.capabilities.contains("IDLE")
                    while !Task.isCancelled {
                        var new = try await conn.search("UID \(lastUID! + 1):*").filter { $0 > lastUID! }.sorted()
                        if resuming { new = Array(new.suffix(backfill)) }
                        if new.isEmpty { try await receive([]) }
                        // Commit each delivered batch so a later fetch failure resumes at that boundary.
                        for start in stride(from: 0, to: new.count, by: 50) {
                            let batch = Array(new[start..<min(start + 50, new.count)])
                            try await receive(batch)
                            await commit(batch.last!)
                        }
                        resuming = false
                        if canIdle {
                            try await conn.idle(renewAfter: 540)
                        } else {
                            try await Task.sleep(for: .seconds(20))
                            _ = try await conn.command("NOOP", timeout: 30)
                        }
                    }
                } onCancel: {
                    Task { await conn.close() }
                }
            } catch {
                await conn.close()
                if Task.isCancelled { break }
                let noPassword = if case IMAPError.noPassword = error { true } else { false }
                let authFailed = noPassword || "\(error)".contains("AUTHENTICATIONFAILED")
                await wait(
                    after: authFailed ? SourceStatus.signInFailed : describe(error),
                    signIn: authFailed, backoff: &backoff, status: status, event: event)
            }
        }
    }

    /// Hands a fetched batch to the app: the check time, the newest message's date, then each message.
    static func hand(
        _ messages: [IncomingMessage], event: @MainActor (SourceEvent) -> Void,
        deliver: @MainActor (IncomingMessage) -> Void
    ) async throws {
        try Task.checkCancellation()
        await event(.checked(Date()))
        if let newest = messages.map(\.date).max() { await event(.message(newest)) }
        for message in messages {
            try Task.checkCancellation()
            await deliver(message)
        }
    }

    /// Shows the failure and waits before the next try: 5 minutes after a sign-in problem, which
    /// retrying soon won't fix, else `backoff`, which doubles up to 2 minutes.
    static func wait(
        after failure: String, signIn: Bool, backoff: inout TimeInterval,
        status: @MainActor (SourceStatus) -> Void, event: @MainActor (SourceEvent) -> Void
    ) async {
        await status(.failed(failure))
        let delay = signIn ? 300 : backoff
        await event(.retry(Date().addingTimeInterval(delay)))
        try? await Task.sleep(for: .seconds(delay))
        backoff = min(backoff * 2, 120)
    }

    /// A failure in plain words, for the source's status. System errors describe themselves as
    /// "The operation couldn't be completed. (Network.NWError error 61…)"; CodeCatch's own read fine.
    static func describe(_ error: Error) -> String {
        switch error {
        case NWError.dns: "Can't find the mail server. Check its name."
        case NWError.posix(.ECONNREFUSED): "The mail server refused the connection. Check its name and port."
        case NWError.tls: "Can't make a secure connection to the mail server."
        case is NWError: "Can't reach the mail server."
        case URLError.badServerResponse: "The mail service sent a reply CodeCatch can't read."
        case is URLError: "Can't reach the mail service."
        case MailAPIError.http(let status, _) where status >= 500: "The mail service is having trouble (\(status)). CodeCatch will try again."
        case MailAPIError.http(let status, _): "The mail service refused the request (\(status))."
        default: error.localizedDescription
        }
    }

    static func imapDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MMM-yyyy"
        return f.string(from: date)
    }
}
