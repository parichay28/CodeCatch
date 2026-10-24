import Combine
import Foundation
import LocalAuthentication
import Testing

@testable import CodeCatch
@testable import CodeCatchCore

@MainActor private final class MonitoringFixture {
    let suite = "MonitoringTests.\(UUID())"
    let defaults: UserDefaults
    let session: VaultSession
    let search: CodeSearch
    private(set) var copied: [String] = []
    private(set) var typed: [String] = []
    private(set) var opened: [URL] = []
    var onConfirmLink: (() -> Bool)?
    private(set) var writes = 0
    private(set) var removals = 0
    var authenticationAllowed = true
    var ownerConfirms = true
    private(set) var ownerChecks = 0
    let stored = [
        VaultCode(
            id: "saved-login", name: "Example", username: nil, domain: nil,
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    ]
    var model: AppModel!

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        for key in ["messagesEnabled", "showHUD", "autoCopy", "sound"] {
            defaults.set(false, forKey: key)
        }
        defaults.set(7, forKey: "historyDays")
        Prefs.register(in: defaults)
        search = CodeSearch(defaults: defaults)
        // Storage stays in memory; no test reaches the keychain or system clipboard.
        session = VaultSession(authenticate: {}, read: { [] }, write: { _ in }, remove: {})
        model = makeModel()
    }

    func makeModel(session: VaultSession? = nil, monitor: SourceMonitor? = nil) -> AppModel {
        let monitor = monitor ?? SourceMonitor(watchMail: { _, _ in }, hasCredential: { _ in false }, defaults: defaults)
        let policy = UnlockPolicy(
            load: { false }, save: { _ in },
            authenticate: { [self] in
                ownerChecks += 1
                if !ownerConfirms { throw CancellationError() }
            })
        return AppModel(
            vaultSession: session ?? self.session, monitor: monitor, search: search,
            defaults: defaults, copyToClipboard: { [weak self] value, _ in self?.copied.append(value) },
            typeCode: { [weak self] code in self?.typed.append(code) },
            unlockPolicy: policy,
            confirmLink: { [self] _, _, _, _ in onConfirmLink?() ?? true },
            openURL: { [weak self] in self?.opened.append($0) })
    }

    func storedSession() -> VaultSession {
        VaultSession(
            authenticate: { [self] in
                if !authenticationAllowed { throw CancellationError() }
            }, read: { [self] in stored }, write: { [self] _ in writes += 1 }, remove: { [self] in removals += 1 })
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }
}

private func monitoringMessage() -> IncomingMessage {
    IncomingMessage(
        text: "Your verification code is 482913. Confirm your sign-in.",
        subject: "Confirm your sign-in", senderName: "Example", senderID: "support@example.com",
        sourceKey: "test-mail", sourceLabel: "Test", date: Date().addingTimeInterval(-300), isMail: true,
        links: [MailLink(url: "https://example.com/verify?token=example", label: "Confirm sign-in")])
}

@MainActor @Suite struct MonitoringTests {
    /// Prevents someone at the Mac, locked or already unlocked, from removing the Touch ID lock without the owner.
    @Test(arguments: [
        (unlocked: false, confirms: false), (unlocked: true, confirms: false),
        (unlocked: false, confirms: true), (unlocked: true, confirms: true),
    ])
    func turningOnUnlockWithMacAlwaysAsksTheOwner(scenario: (unlocked: Bool, confirms: Bool)) async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        if scenario.unlocked { try await fixture.session.unlock() }
        fixture.ownerConfirms = scenario.confirms
        await fixture.model.setUnlockWithMac(true)

        #expect(fixture.ownerChecks == 1)
        #expect(fixture.model.isOn(Prefs.unlockWithMac) == scenario.confirms)
        #expect(fixture.model.isUnlocked == (scenario.unlocked || scenario.confirms))
    }

    /// Turning "Unlock with Your Mac" off must hide codes now, not at the next sleep, and must not be blockable.
    @Test func turningOffUnlockWithMacLocksAtOnceWithoutAskingTheOwner() async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        await fixture.model.setUnlockWithMac(true)
        try #require(fixture.model.isUnlocked)
        fixture.ownerConfirms = false
        await fixture.model.setUnlockWithMac(false)

        #expect(fixture.ownerChecks == 1)
        #expect(!fixture.model.isOn(Prefs.unlockWithMac))
        #expect(!fixture.model.isUnlocked)
    }

    @Test func writableUnlockPreferenceCannotBypassProtectedConsentOrAuthentication() async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(true, forKey: Prefs.unlockWithMac)
        fixture.authenticationAllowed = false
        let model = fixture.makeModel(session: fixture.storedSession())
        #expect(!model.isOn(Prefs.unlockWithMac))
        await #expect(throws: (any Error).self) { try await model.authenticate() }
        #expect(!model.isUnlocked)
    }

    enum RetainedRemoval: CaseIterable { case ignore, dismiss, clear, disableFeatures }

    @Test(arguments: RetainedRemoval.allCases)
    func removedReceivedRowCannotCopyCodeCopyLinkOrOpen(_ removal: RetainedRemoval) async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        fixture.model.ingest(monitoringMessage())
        let retained = try #require(fixture.model.items.first { !$0.code.isEmpty && $0.link != nil })
        try await fixture.session.unlock()
        switch removal {
        case .ignore: fixture.model.ignore("support@example.com")
        case .dismiss: fixture.model.dismiss(retained)
        case .clear: fixture.model.clearHistory()
        case .disableFeatures:
            fixture.model.set(Prefs.receivedCodes, on: false)
            fixture.model.set(Prefs.signInLinks, on: false)
        }
        try #require(fixture.model.items.isEmpty)
        fixture.model.copy(retained)
        fixture.model.copyLink(retained)
        fixture.model.open(retained)
        #expect(fixture.copied.isEmpty)
        #expect(fixture.opened.isEmpty)
    }

    @Test(arguments: RetainedRemoval.allCases)
    func removalDuringLinkConfirmationPreventsLateOpen(_ removal: RetainedRemoval) async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        var message = monitoringMessage()
        message.senderID = "support@other.example"
        fixture.model.ingest(message)
        let retained = try #require(fixture.model.items.first { $0.link != nil })
        try #require(retained.linkNotice?.warns == true)
        try await fixture.session.unlock()
        var confirmations = 0
        fixture.onConfirmLink = {
            confirmations += 1
            switch removal {
            case .ignore: fixture.model.ignore("support@other.example")
            case .dismiss: fixture.model.dismiss(retained)
            case .clear: fixture.model.clearHistory()
            case .disableFeatures: fixture.model.set(Prefs.signInLinks, on: false)
            }
            return true
        }
        fixture.model.open(retained)
        #expect(confirmations == 1)
        #expect(fixture.opened.isEmpty)
    }

    @Test(arguments: [false, true])
    func identicalCodeAndDateFromDifferentSendersOrAccountsStaySeparate(_ differentAccount: Bool) throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        let first = monitoringMessage()
        var second = first
        if differentAccount {
            second.sourceKey = "other-mail-account"
            second.sourceLabel = "Other account"
        } else {
            second.senderID = "security@other.example"
        }
        fixture.model.ingest(first)
        fixture.model.ingest(second)
        let rows = fixture.model.items.filter { $0.code == "482913" }
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.id)).count == 2)
        if differentAccount {
            #expect(Set(rows.map(\.sourceKey)) == Set([first.sourceKey, second.sourceKey]))
        } else {
            #expect(rows.contains { $0.sender == first.senderID })
            #expect(rows.contains { $0.sender == second.senderID })
        }
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func ingestionDoesNotLeakDisabledPortionsOfMixedMail(codes: Bool, links: Bool) throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        fixture.model.set(Prefs.receivedCodes, on: codes)
        fixture.model.set(Prefs.signInLinks, on: links)
        fixture.model.ingest(monitoringMessage())

        #expect(fixture.model.items.contains { !$0.code.isEmpty } == codes)
        #expect(fixture.model.items.contains { $0.link != nil } == links)
        if !codes && !links { #expect(fixture.model.items.isEmpty) }
    }

    /// Each link kind follows its own setting: turning off sign-in links must not hide resets, and the reverse.
    @Test(arguments: [(true, false), (false, true)])
    func passwordResetLinksFollowTheirOwnSetting(signIn: Bool, reset: Bool) throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        fixture.model.set(Prefs.signInLinks, on: signIn)
        fixture.model.set(Prefs.resetLinks, on: reset)
        let mail = { (subject: String, label: String) in
            IncomingMessage(
                text: label, subject: subject, senderName: "Example", senderID: "support@example.com",
                sourceKey: "test-mail", sourceLabel: "Test", date: Date().addingTimeInterval(-300), isMail: true,
                links: [MailLink(url: "https://example.com/\(label.count)?token=t", label: label)])
        }
        fixture.model.ingest(mail("Reset your password", "Reset password"))
        fixture.model.ingest(mail("Confirm your sign-in", "Confirm sign-in"))

        #expect(fixture.model.items.contains { $0.resetsPassword } == reset)
        #expect(fixture.model.items.contains { !$0.resetsPassword } == signIn)

        fixture.model.set(Prefs.signInLinks, on: false)
        fixture.model.set(Prefs.resetLinks, on: false)
        #expect(fixture.model.items.isEmpty)
    }

    @Test(arguments: [true, false])
    func disablingOnePortionKeepsTheOtherAndReingestionRestoresReenabledContent(disableCodes: Bool) throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        let message = monitoringMessage()
        fixture.model.ingest(message)
        #expect(fixture.model.items.contains { !$0.code.isEmpty })
        #expect(fixture.model.items.contains { $0.link != nil })
        let disabledKey = disableCodes ? Prefs.receivedCodes : Prefs.signInLinks
        fixture.model.set(disabledKey, on: false)

        #expect(fixture.model.items.contains { !$0.code.isEmpty } == !disableCodes)
        #expect(fixture.model.items.contains { $0.link != nil } == disableCodes)

        fixture.model.set(disabledKey, on: true)
        fixture.model.ingest(message)
        #expect(fixture.model.items.contains { !$0.code.isEmpty })
        #expect(fixture.model.items.contains { $0.link != nil })

        fixture.model.set(Prefs.receivedCodes, on: false)
        fixture.model.set(Prefs.signInLinks, on: false)
        #expect(fixture.model.items.isEmpty)
        fixture.model.ingest(message)
        #expect(fixture.model.items.isEmpty)
    }

    @Test(arguments: [true, false])
    func disablingReceivedContentBlocksPreviouslyVisibleRowsEvenAfterUnlock(code: Bool) async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        let message = IncomingMessage(
            text: code ? "Your verification code is 482913." : "Confirm your sign-in.",
            subject: "Confirm your sign-in", senderName: "Example", senderID: "support@example.com",
            sourceKey: "test-mail", sourceLabel: "Test", date: Date().addingTimeInterval(-300), isMail: true,
            links: code ? [] : [MailLink(url: "https://example.com/verify?token=example", label: "Confirm sign-in")])
        fixture.model.ingest(message)
        let retained = try #require(fixture.model.items.first)
        try await fixture.session.unlock()
        fixture.model.copy(retained)
        #expect(fixture.copied == [retained.copyValue])

        fixture.model.set(code ? Prefs.receivedCodes : Prefs.signInLinks, on: false)
        #expect(fixture.model.items.isEmpty)
        fixture.model.copy(retained)
        #expect(fixture.copied.count == 1)
        fixture.session.lock()
        try await fixture.session.unlock()
        fixture.model.copy(retained)
        #expect(fixture.copied.count == 1)
    }

    /// Prevents a code being typed into the front app when not opted in, locked, unmonitored, stale, or already typed.
    @Test(arguments: [
        (autoType: true, unlocked: true, monitored: true, hasCode: true, age: 0.0, types: true),
        (autoType: false, unlocked: true, monitored: true, hasCode: true, age: 0.0, types: false),
        (autoType: true, unlocked: false, monitored: true, hasCode: true, age: 0.0, types: false),
        (autoType: true, unlocked: true, monitored: false, hasCode: true, age: 0.0, types: false),
        (autoType: true, unlocked: true, monitored: true, hasCode: false, age: 0.0, types: false),
        (autoType: true, unlocked: true, monitored: true, hasCode: true, age: 300.0, types: false),
    ])
    func codeIsTypedOnceOnlyWhenOptedInUnlockedMonitoredAndJustArrived(
        scenario: (autoType: Bool, unlocked: Bool, monitored: Bool, hasCode: Bool, age: TimeInterval, types: Bool)
    ) async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        #expect(!fixture.defaults.bool(forKey: Prefs.autoType))
        fixture.defaults.set(scenario.autoType, forKey: Prefs.autoType)
        fixture.model.set(Prefs.receivedCodes, on: scenario.monitored)
        if scenario.unlocked { try await fixture.session.unlock() }
        let message = IncomingMessage(
            text: scenario.hasCode ? "Your verification code is 482913." : "Confirm your sign-in.",
            subject: "Confirm your sign-in", senderName: "Example", senderID: "support@example.com",
            sourceKey: "test-mail", sourceLabel: "Test", date: Date().addingTimeInterval(-scenario.age), isMail: true,
            links: scenario.hasCode ? [] : [MailLink(url: "https://example.com/verify?token=example", label: "Confirm sign-in")])

        fixture.model.ingest(message)
        fixture.model.ingest(message)
        #expect(fixture.model.items.contains { $0.code == "482913" } == (scenario.hasCode && scenario.monitored))
        // Unlocking afterwards must not type a code that arrived while locked.
        try await fixture.model.unlock()
        #expect(fixture.typed == (scenario.types ? ["482913"] : []))
    }

    @Test func mixedRowCopyLinkRequiresAuthenticationAndRejectsDisabledRetainedLinks() async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        fixture.model.ingest(monitoringMessage())
        let retained = try #require(fixture.model.items.first { !$0.code.isEmpty && $0.link != nil })
        let link = try #require(retained.link)

        fixture.model.copyLink(retained)
        #expect(fixture.copied.isEmpty)
        try await fixture.session.unlock()
        fixture.model.copyLink(retained)
        #expect(fixture.copied == [link.absoluteString])

        fixture.model.set(Prefs.signInLinks, on: false)
        fixture.model.copyLink(retained)
        #expect(fixture.copied.count == 1)
        fixture.session.lock()
        try await fixture.session.unlock()
        fixture.model.copyLink(retained)
        #expect(fixture.copied.count == 1)
    }

    @Test func newModelsHonorSavedMonitoringChoices() throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        for key in [Prefs.receivedCodes, Prefs.signInLinks, Prefs.resetLinks, Prefs.bitwarden] {
            fixture.model.set(key, on: false)
            #expect(!fixture.defaults.bool(forKey: key))
        }
        let restored = fixture.makeModel()
        restored.ingest(monitoringMessage())
        #expect(restored.items.isEmpty)
        #expect(restored.vaultItems.isEmpty)
        restored.set(Prefs.signInLinks, on: true)
        let next = fixture.makeModel()
        next.ingest(monitoringMessage())
        #expect(next.items.contains { $0.link != nil })
        #expect(next.items.allSatisfy { $0.code.isEmpty })
    }

    @Test func disablingBitwardenLocksWithoutDeletingAndBlocksRetainedRowsAfterUnlock() async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        let session = fixture.storedSession()
        let model = fixture.makeModel(session: session)
        try await session.unlock()
        let retained = try #require(model.vaultItems.first)
        model.set(Prefs.bitwarden, on: false)

        #expect(!session.isUnlocked)
        #expect(model.vaultItems.isEmpty)
        #expect(fixture.writes == 0)
        #expect(fixture.removals == 0)
        model.copy(retained)
        try await session.unlock()
        #expect(session.codes.map(\.id) == fixture.stored.map(\.id))
        #expect(model.vaultItems.isEmpty)
        model.copy(retained)
        #expect(fixture.copied.isEmpty)
        #expect(fixture.search.recents.isEmpty)

        model.set(Prefs.bitwarden, on: true)
        try await session.unlock()
        #expect(model.vaultItems.map(\.sourceKey) == fixture.stored.map(\.id))
        model.copy(retained)
        #expect(fixture.copied.count == 1)
    }

    @Test func disablingBitwardenDoesNotBypassAuthenticationForReceivedCodes() async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        let session = fixture.storedSession()
        let model = fixture.makeModel(session: session)
        model.set(Prefs.bitwarden, on: false)
        model.ingest(monitoringMessage())
        let item = try #require(model.items.first { !$0.code.isEmpty })
        fixture.authenticationAllowed = false
        model.copy(item)
        await model.unlocked { model.copy(item) }?.value
        #expect(!model.isUnlocked)
        #expect(fixture.copied.isEmpty)

        fixture.authenticationAllowed = true
        await model.unlocked { model.copy(item) }?.value
        #expect(fixture.copied == ["482913"])
        session.lock()
        model.copy(item)
        #expect(fixture.copied == ["482913"])
    }

    /// A failed unlock from a click on a code used to do nothing at all; closing the prompt stays quiet.
    @Test(arguments: [(LAError(.authenticationFailed) as any Error, true), (LAError(.userCancel), false), (CancellationError(), false)])
    func unlockFailuresAreShownButCancelsAreNot(error: any Error, shown: Bool) async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel(session: VaultSession(authenticate: { throw error }, read: { [] }, write: { _ in }, remove: {}))
        var ran = false
        await model.unlocked { ran = true }?.value
        #expect(!ran)
        #expect((model.unlockError != nil) == shown)
    }

    @Test func disabledMailRejectsOldCallbacksAndCannotRestartUntilOneFeatureIsEnabled() async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        let account = MailAccount(label: "Test", host: "example.invalid", user: "test@example.invalid")
        let key = account.id.uuidString
        let starts = AsyncStream<SourceMonitor.Callbacks>.makeStream()
        let stops = AsyncStream<Void>.makeStream()
        var started = starts.stream.makeAsyncIterator()
        var stopped = stops.stream.makeAsyncIterator()
        var startCount = 0
        var delivered = 0
        let monitor = SourceMonitor(
            watchMail: { _, callback in
                startCount += 1
                starts.continuation.yield(callback)
                defer { stops.continuation.yield(()) }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }, hasCredential: { _ in true }, defaults: fixture.defaults)
        monitor.deliver = { _ in delivered += 1 }
        monitor.restartMail([account])
        let original = try #require(await started.next())
        original.status(.live)
        original.deliver(monitoringMessage())
        #expect(delivered == 1)

        fixture.defaults.set(false, forKey: Prefs.receivedCodes)
        fixture.defaults.set(false, forKey: Prefs.signInLinks)
        fixture.defaults.set(false, forKey: Prefs.resetLinks)
        monitor.restartMail([account])
        _ = await stopped.next()
        original.status(.live)
        original.event(.checked(Date()))
        original.deliver(monitoringMessage())
        #expect(delivered == 1)
        #expect(monitor.health[key]?.status == .off)
        #expect(monitor.health[key]?.lastChecked == nil)

        monitor.check(key)
        monitor.networkChanged(online: false, interfaces: [])
        monitor.networkChanged(online: true, interfaces: ["en0"])
        monitor.networkChanged(online: true, interfaces: ["en1"])
        await Task.yield()
        #expect(startCount == 1)
        #expect(monitor.health[key]?.status == .off)

        fixture.defaults.set(true, forKey: Prefs.signInLinks)
        monitor.restartMail([account])
        let current = try #require(await started.next())
        #expect(startCount == 2)
        current.status(.live)
        current.deliver(monitoringMessage())
        #expect(monitor.health[key]?.status == .live)
        #expect(delivered == 2)
        monitor.restartMail([])
        _ = await stopped.next()
    }

    /// "Not a Code" drops the wrong code and skips the next message like it (not even as a missed email),
    /// lets the sender's real codes through, survives a relaunch without keeping message text, and undoes.
    @Test func notACodeSkipsMessagesLikeItAndUndoes() throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        func mail(_ text: String, id: String) -> IncomingMessage {
            IncomingMessage(
                text: text, senderName: "Clinic", senderID: "noreply@clinic.example", sourceKey: "test-mail",
                sourceLabel: "Test", date: Date().addingTimeInterval(-60), isMail: true, messageID: id)
        }
        fixture.model.ingest(mail("Appointment confirmed for 1430 on Tuesday.", id: "1"))
        #expect(fixture.model.items.map(\.code) == ["1430"])
        fixture.model.markNotCode(fixture.model.items[0])
        #expect(fixture.model.items.isEmpty)

        fixture.model.ingest(mail("Appointment confirmed for 1515 on Tuesday.", id: "2"))
        #expect(fixture.model.items.isEmpty)
        #expect(fixture.model.recovery.entries.isEmpty)
        fixture.model.ingest(mail("Your code is 482913.", id: "3"))
        #expect(fixture.model.items.map(\.code) == ["482913"])

        let relaunched = fixture.makeModel()
        #expect(relaunched.notCodes.map(\.sender) == ["noreply@clinic.example"])
        let stored = String(decoding: fixture.defaults.data(forKey: Prefs.notCodes) ?? Data(), as: UTF8.self).lowercased()
        #expect(!stored.isEmpty && !stored.contains("appointment") && !stored.contains("tuesday"))
        relaunched.forgetNotCodes(Set(relaunched.notCodes.map(\.key)))
        #expect(relaunched.notCodes.isEmpty)
        relaunched.ingest(mail("Appointment confirmed for 1515 on Tuesday.", id: "4"))
        #expect(relaunched.items.map(\.code) == ["1515"])

        // Never for a test code (marking one would silence Show Test Code), nor a row left with only its link.
        relaunched.showTestCode()
        let test = try #require(relaunched.items.first { $0.origin == .test })
        relaunched.markNotCode(test)
        #expect(relaunched.notCodes.isEmpty && relaunched.items.contains { $0.id == test.id })
        relaunched.ingest(monitoringMessage())
        relaunched.set(Prefs.receivedCodes, on: false)
        let link = try #require(relaunched.items.first { $0.link != nil })
        relaunched.markNotCode(link)
        #expect(relaunched.notCodes.isEmpty && relaunched.items.contains { $0.id == link.id })
    }

    /// Prevents a code being typed scrambled with another, after permission was withdrawn, or into a held shortcut.
    @Test func keyTyperPressesWholeTextsInOrderAndOnlyWhileStillAllowed() async {
        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var text = ""
            func press(_ character: Character) { lock.withLock { text.append(character) } }
            var pressed: String { lock.withLock { text } }
        }
        let recorder = Recorder()
        var revoked = true
        var granted = false
        let type = { (text: String, allowed: @escaping @MainActor () -> Bool, held: Bool) in
            KeyTyper.type(text, allowed: allowed, modifiersHeld: { held }, press: recorder.press)
        }
        type("123", { true }, false)
        type("456", { true }, false)
        type("777", { revoked }, false)
        type("89", { granted }, false)
        // Flipped before the main actor is released, so only a call-time evaluation sees the old values.
        revoked = false
        granted = true
        type("000", { true }, true)
        await withCheckedContinuation { done in KeyTyper.queue.async { done.resume() } }
        #expect(recorder.pressed == "12345689")
    }

    /// The once-a-second clock redrew every observing view, so the closed menu rebuilt its list each second
    /// (2% CPU at idle). With no window open it may only redraw when the menu bar label changes.
    @Test func clockRedrawsAClosedMenuOnlyWhenTheMenuBarLabelChanges() throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        let start = Date()
        fixture.model.ingest(
            IncomingMessage(
                text: "Your verification code is 482913.", senderName: "Example", senderID: "support@example.com",
                sourceKey: "test-mail", sourceLabel: "Test", date: start, isMail: true))
        try #require(fixture.model.latestCode != nil)
        var redraws = 0
        let observation = fixture.model.objectWillChange.sink { redraws += 1 }
        defer { observation.cancel() }

        for second in [1.0, 2, 60, 179] { fixture.model.tick(at: start + second) }
        #expect(redraws == 0)
        fixture.model.tick(at: start + 181)  // the code leaves the menu bar
        #expect(redraws == 1)
        for second in [182.0, 300, 599] { fixture.model.tick(at: start + second) }
        #expect(redraws == 1)
        fixture.model.tick(at: start + 601)  // no longer recent
        #expect(redraws == 2)
    }

    /// Messages records a check every second, and each one redrew every view, the closed menu's too.
    @Test func aSourceCheckAloneRedrawsNothing() async throws {
        let fixture = try MonitoringFixture()
        defer { fixture.cleanUp() }
        let account = MailAccount(label: "Test", host: "example.invalid", user: "test@example.invalid")
        let starts = AsyncStream<SourceMonitor.Callbacks>.makeStream()
        var started = starts.stream.makeAsyncIterator()
        let monitor = SourceMonitor(
            watchMail: { _, callbacks in
                starts.continuation.yield(callbacks)
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }, hasCredential: { _ in true }, defaults: fixture.defaults)
        let model = fixture.makeModel(monitor: monitor)
        monitor.restartMail([account])
        let callbacks = try #require(await started.next())
        var redraws = 0
        let observation = model.objectWillChange.sink { redraws += 1 }
        defer { observation.cancel() }

        for second in 1...3 { callbacks.event(.checked(Date(timeIntervalSince1970: Double(second)))) }
        #expect(redraws == 0)
        #expect(monitor.health[account.id.uuidString]?.lastChecked == Date(timeIntervalSince1970: 3))
        callbacks.status(.live)
        #expect(redraws == 1)
        monitor.restartMail([])
    }
}
