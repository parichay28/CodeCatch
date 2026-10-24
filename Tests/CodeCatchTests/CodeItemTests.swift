import AppKit
import Testing

@testable import CodeCatch
@testable import CodeCatchCore

private func message(_ text: String, at date: Date) -> IncomingMessage {
    IncomingMessage(
        text: text, senderName: "Example", senderID: "sender@example.com",
        sourceKey: "account", sourceLabel: "Test", date: date, isMail: true)
}

@Test func dismissalsDistinguishMessagesEvenFromTheSameSenderAndSecond() {
    var first = message("Your code is 482913", at: Date(timeIntervalSince1970: 1_700_000_000))
    first.messageID = "101"
    var second = first
    second.messageID = "102"
    #expect(CodeItem(first, code: "482913", link: nil).dismissKey != CodeItem(second, code: "482913", link: nil).dismissKey)
}

@Test func dismissalDoesNotPersistCodesOrSignInTokens() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let code = CodeItem(message("Your code is 482913", at: date), code: "482913", link: nil)
    let link = CodeItem(message("Sign in", at: date), code: nil, link: URL(string: "https://example.com/login?token=private-token")!)
    #expect(!code.dismissKey.contains(code.code))
    #expect(!link.dismissKey.contains("private-token"))
    #expect(code.dismissKey == CodeItem(message("Your code is 482913", at: date), code: "482913", link: nil).dismissKey)
}

/// "Not a Code" must cover the next message of the same kind from that sender, whatever its numbers, and
/// never that sender's real codes, another sender's messages, or a code introduced in other words.
@Test func notACodeMatchesOnlyTheSameKindOfMessageFromTheSameSender() throws {
    func key(_ text: String, from sender: String = "+4915550100") throws -> String {
        let message = IncomingMessage(
            text: text, senderName: "", senderID: sender, sourceKey: "test", sourceLabel: "Test", date: Date(), isMail: sender.contains("@"))
        return CodeItem.notCodeKey(for: try #require(CodeExtractor.detect(in: text), "\(text)"), from: message)
    }
    let marked = try key("Appointment confirmed for 1430 on Tuesday.")
    #expect(try key("Appointment confirmed for 1515 on Tuesday.") == marked)
    #expect(try key("Your code is 482913.") != marked)
    #expect(try key("Appointment confirmed for 1430 on Tuesday.", from: "+4915550199") != marked)
    // The number the extractor chose, not the first place its digits appear ("1430" inside 1143099).
    #expect(try key("Ref: 1143099\nAppointment confirmed for 1430 on Tuesday.") == key("Ref: 1777799\nAppointment confirmed for 1515 on Tuesday."))
    #expect(try key("Ref: 14829139\nYour code is 482913.") != key("Ref: 1143099\nAppointment confirmed for 1430 on Tuesday."))
    // A number alone on its line is told apart by the line above it.
    #expect(try key("Appointment confirmation:\n1430") != key("Your sign-in code:\n482913"))
    // Read as the extractor reads it: without direction marks.
    #expect(try key("Your code: AB\u{200E}12CD") == key("Your code: EF\u{200E}34GH"))
    // A site-bound footer ("@site #code") reads the same on every message: the text above tells them apart.
    #expect(try key("Appointment confirmed for 1430.\n@clinic.example #1430") != key("Your sign-in code is 482913.\n@clinic.example #482913"))
    #expect(try key("Your code is 1430\u{200E}.\n@clinic.example #1430") == key("Your code is 1515.\n@clinic.example #1515"))
    // ...whatever its per-message link or letter code.
    #expect(
        try key("Appointment confirmed for 1430. Details: https://clinic.example/a/Xy7Kq\n@clinic.example #1430")
            == key("Appointment confirmed for 1515. Details: https://clinic.example/a/Pz8Lm\n@clinic.example #1515"))
    #expect(try key("Booking confirmed: AB12CD.\n@clinic.example #AB12CD") == key("Booking confirmed: EF34GH.\n@clinic.example #EF34GH"))
    #expect(try key("预约已确认，预约码为AB12CD。\n@clinic.example #AB12CD") == key("预约已确认，预约码为EF34GH。\n@clinic.example #EF34GH"))
    #expect(
        try key("Appointment confirmed for 1430. Ref: 1143099.\n@clinic.example #1430")
            == key("Appointment confirmed for 1515. Ref: 1777799.\n@clinic.example #1515"))
    // Mail by domain: a shop writes from more than one address.
    #expect(
        try key("Appointment confirmed for 1430 on Tuesday.", from: "bookings@clinic.example")
            == key("Appointment confirmed for 1515 on Tuesday.", from: "noreply@clinic.example"))
    // Text without spaces keeps its words: only the digits are masked.
    #expect(try key("【京东】验证码：548393，您正在新设备上登录。") != key("【京东】确认订单548393已发货，订单验证码"))
}

@Test(arguments: [(90.0, false), (30.0, false), (29.0, true), (-1.0, true)])
func expiredCodesDoNotTriggerAutomaticCopyWhileClockSkewStillWorks(age: TimeInterval, expected: Bool) {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let item = CodeItem(message("Your code is 482913. Valid for 30 seconds.", at: now.addingTimeInterval(-age)), code: "482913", link: nil)
    #expect(item.shouldAnnounce(at: now) == expected)
}

/// A link valid for 24 hours must not hold the popover's top card all day; an expired code must not take it either.
@Test(arguments: [
    ("This link will expire in 24 hours.", 540.0, true), ("This link will expire in 24 hours.", 660.0, false),
    ("Valid for 5 minutes.", 240.0, true), ("Valid for 5 minutes.", 360.0, false),
])
func topCardShowsOnlyARecentLiveItem(text: String, age: TimeInterval, expected: Bool) {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let item = CodeItem(message(text, at: now.addingTimeInterval(-age)), code: nil, link: URL(string: "https://example.com/reset")!)
    #expect(item.isRecent(at: now) == expected)
}

@Suite(.serialized) struct ClipboardTests {
    @Test @MainActor func rotatedTOTPDoesNotClaimThePreviousCodeIsCopied() throws {
        let vault = VaultCode(
            id: UUID().uuidString, name: "Example", username: nil, domain: nil,
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        let previous = try #require(CodeItem(vault, at: Date(timeIntervalSince1970: 59)))
        let current = try #require(CodeItem(vault, at: Date(timeIntervalSince1970: 60)))
        #expect(previous.code != current.code)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        Clipboard.copy(previous.code, id: previous.id, pasteboard: pasteboard)
        #expect(Clipboard.holds(previous, pasteboard: pasteboard))
        #expect(!Clipboard.holds(current, pasteboard: pasteboard))
        Clipboard.copy(current.code, id: current.id, pasteboard: pasteboard)
        #expect(Clipboard.holds(current, pasteboard: pasteboard))
        pasteboard.clearContents()
        pasteboard.setString("unrelated", forType: .string)
        #expect(!Clipboard.holds(current, pasteboard: pasteboard))
    }

    /// "Not a Code" must not wipe a clipboard that has moved on from the item's own code: not the same row's
    /// sign-in link, not something copied elsewhere, not another item's code.
    @Test @MainActor func notACodeEmptiesOnlyTheClipboardThatStillHoldsTheItemsOwnCode() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let link = try #require(URL(string: "https://example.com/login"))
        let item = CodeItem(message("Your code is 482913", at: date), code: "482913", link: link)
        let other = CodeItem(message("Your code is 771024", at: date), code: "771024", link: nil)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        func clear(after copy: () -> Void) -> String? {
            Clipboard.copy(item.code, id: item.id, pasteboard: pasteboard)
            copy()
            Clipboard.clearIfHolds(item, pasteboard: pasteboard)
            return pasteboard.string(forType: .string)
        }
        #expect(clear(after: {}) == nil)
        #expect(clear(after: { Clipboard.copy(link.absoluteString, id: item.id, pasteboard: pasteboard) }) == link.absoluteString)
        #expect(
            clear(after: {
                pasteboard.clearContents()
                pasteboard.setString("unrelated", forType: .string)
            }) == "unrelated")
        #expect(clear(after: { Clipboard.copy(other.code, id: other.id, pasteboard: pasteboard) }) == other.code)
    }
}

/// What the card says about the link: nothing on the sender's own site, a warning when the site differs or
/// the sender can't be read (lookalike, port, empty), and only a calm note when the mail server verified it.
@Test(arguments: [
    ("team@notion.so", "https://www.notion.so/login", nil as Bool?, nil as Bool?), ("team@notion.so", "https://evil.com/login", nil, true),
    ("team@nоtion.so", "https://evil.com/login", nil, true), ("team@evil.com:8443", "https://evil.com/login", nil, true),
    ("", "https://evil.com/login", nil, true),
    // The scanner's destination is what counts.
    ("team@notion.so", "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fwww.notion.so%2Flogin", nil, nil),
    ("team@notion.so", "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fevil.com%2Flogin", nil, true),
    // Verified: another site is the sender's own choice, said calmly. Failed: never a pass, even on its own domain.
    ("team@notion.so", "https://notion-static.com/login", true, false), ("team@notion.so", "https://sites.notion.so/evil-login", false, true),
])
func linkNotice(sender: String, link: String, verified: Bool?, warns: Bool?) {
    var mail = IncomingMessage(
        text: "Sign in", senderName: "Notion", senderID: sender, sourceKey: "account", sourceLabel: "Test",
        date: Date(timeIntervalSince1970: 1_700_000_000), isMail: true)
    mail.senderVerified = verified
    #expect(CodeItem(mail, code: nil, link: URL(string: link)!).linkNotice?.warns == warns)
}

/// Two Gmail accounts both labelled "Gmail" must not read the same; a mailbox whose badge is its own needs no name.
@MainActor @Test func mailOriginationNamesTheMailboxOnlyWhenItIsAmbiguous() throws {
    let suite = "Origination.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = MailAccount(label: "Gmail", host: "imap.gmail.com", user: "first@gmail.com")
    let second = MailAccount(label: "Gmail", host: "imap.gmail.com", user: "second@gmail.com")
    let work = MailAccount(label: "Work", host: "imap.example.com", user: "me@example.com")
    func model(_ accounts: [MailAccount]) -> AppModel {
        AppModel(
            vaultSession: VaultSession(authenticate: {}, read: { [] }, write: { _ in }, remove: {}),
            monitor: SourceMonitor(watchMail: { _, _ in }, hasCredential: { _ in false }, defaults: defaults),
            defaults: defaults, accounts: accounts, copyToClipboard: { _, _ in })
    }
    func item(_ account: MailAccount) -> CodeItem {
        CodeItem(
            IncomingMessage(
                text: "Your code is 482913", senderName: "Example", senderID: "sender@example.com",
                sourceKey: account.id.uuidString, sourceLabel: account.label, date: Date(), isMail: true),
            code: "482913", link: nil)
    }
    #expect(model([first]).origination(item(first)) == "")
    let several = model([first, second, work])
    #expect(several.origination(item(first)) == "first@gmail.com")
    #expect(several.origination(item(work)) == "")
    let personal = MailAccount(label: "Personal", host: "imap.gmail.com", user: "me@gmail.com")
    #expect(model([first, personal]).origination(item(personal)) == "Personal")
    // Logos off, every mailbox wears the mail app's badge: the name is all that tells them apart.
    defaults.set(false, forKey: Prefs.serviceIcons)
    #expect(model([first, work]).origination(item(work)) == "Work")
}

/// "Show in …" must open the email in the account it came to, and a text's own conversation.
@MainActor @Test func showInSourceOpensTheExactEmailOrConversation() throws {
    let suite = "Source.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(
        vaultSession: VaultSession(authenticate: {}, read: { [] }, write: { _ in }, remove: {}),
        monitor: SourceMonitor(watchMail: { _, _ in }, hasCredential: { _ in false }, defaults: defaults),
        defaults: defaults, accounts: [], copyToClipboard: { _, _ in })
    let gmail = MailAccount(label: "Gmail", host: "imap.gmail.com", user: "second@gmail.com")
    var mail = IncomingMessage(
        text: "Your code is 482913", senderName: "Example", senderID: "sender@example.com",
        sourceKey: gmail.id.uuidString, sourceLabel: "Gmail", date: Date(), isMail: true)
    mail.webURL = GmailAPI.webURL("18c2f", account: gmail)
    // Even with a Message-ID and Mail as the mail app: an API account's email may not be in Mail at all.
    mail.internetMessageID = "a1b2.c3@mail.example.com"
    let fromGmail = try #require(model.source(of: CodeItem(mail, code: "482913", link: nil)))
    // Gmail answers 404 to /mail/u/<address>/; ?authuser= picks the account (or asks to sign in to it).
    #expect(fromGmail.url.absoluteString == "https://mail.google.com/mail/?authuser=second@gmail.com#all/18c2f")
    let text = IncomingMessage(
        text: "Your code is 482913", senderName: "", senderID: "22000",
        sourceKey: MessagesStore.sourceKey, sourceLabel: "Messages", date: Date(), isMail: false)
    #expect(model.source(of: CodeItem(text, code: "482913", link: nil))?.url.absoluteString == "sms:22000")
    // A named sender ("Revolut") has no address: sms:Revolut would start a message to nobody.
    var named = text
    named.senderID = "Revolut"
    #expect(model.source(of: CodeItem(named, code: "482913", link: nil))?.url.scheme != "sms")
}

@MainActor private final class LinkRecorder {
    var opened: [URL] = []
    var asked = 0
}

/// A phishing link must never open without an explicit Open: not on Cancel, not via "Show in …", not after a lock mid-alert.
@MainActor @Test func suspectLinkOpensOnlyOnExplicitConsent() async throws {
    enum Choice { case cancel, showEmail, open, lockThenOpen }
    func run(sender: String, _ choice: Choice, lockedFirst: Bool = false) async throws
        -> (item: CodeItem, link: URL, opened: [URL], asked: Int, used: Bool, email: URL?)
    {
        let suite = "LinkConsent.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in [Prefs.showBanner, Prefs.autoCopy, Prefs.sound] { defaults.set(false, forKey: key) }
        Prefs.register(in: defaults)
        let session = VaultSession(authenticate: {}, read: { [] }, write: { _ in }, remove: {})
        let recorder = LinkRecorder()
        let gmail = MailAccount(label: "Gmail", host: "imap.gmail.com", user: "me@gmail.com")
        let model = AppModel(
            vaultSession: session,
            monitor: SourceMonitor(watchMail: { _, _ in }, hasCredential: { _ in false }, defaults: defaults),
            defaults: defaults, accounts: [gmail], copyToClipboard: { _, _ in },
            confirmLink: { _, _, _, email in
                recorder.asked += 1
                switch choice {
                case .cancel: return false
                case .showEmail:
                    email?.run()
                    return false
                case .open: return true
                case .lockThenOpen:
                    session.lock()
                    return true
                }
            },
            openURL: { recorder.opened.append($0) })
        try await session.unlock()
        var mail = IncomingMessage(
            text: "Confirm it was you.", subject: "Verify your sign-in", senderName: "Acme", senderID: sender,
            sourceKey: gmail.id.uuidString, sourceLabel: "Gmail", date: Date().addingTimeInterval(-30), isMail: true,
            links: [MailLink(url: "https://acme-secure-login.net/verify?t=1", label: "Verify sign-in")])
        mail.webURL = GmailAPI.webURL("18c2f", account: gmail)
        model.ingest(mail)
        let item = try #require(model.items.first { $0.isLink })
        if lockedFirst { session.lock() }
        model.open(item)
        return (
            item, try #require(item.link), recorder.opened, recorder.asked, model.items.first { $0.id == item.id }?.used ?? false, model.source(of: item)?.url
        )
    }
    let phish = "security@acme.com"

    let cancel = try await run(sender: phish, .cancel)
    #expect(cancel.item.linkNotice?.warns == true)
    #expect(cancel.asked == 1 && cancel.opened.isEmpty && !cancel.used)

    let show = try await run(sender: phish, .showEmail)
    let email = try #require(show.email)
    #expect(show.asked == 1 && show.opened == [email] && !show.used)
    #expect(!show.opened.contains(show.link))

    let open = try await run(sender: phish, .open)
    #expect(open.asked == 1 && open.opened == [open.link] && open.used)

    let lockedDuringAlert = try await run(sender: phish, .lockThenOpen)
    #expect(lockedDuringAlert.asked == 1 && lockedDuringAlert.opened.isEmpty)

    let locked = try await run(sender: phish, .open, lockedFirst: true)
    #expect(locked.asked == 0 && locked.opened.isEmpty)

    let ownSite = try await run(sender: "security@acme-secure-login.net", .cancel)
    #expect(ownSite.item.linkNotice == nil)
    #expect(ownSite.asked == 0 && ownSite.opened == [ownSite.link])
}
