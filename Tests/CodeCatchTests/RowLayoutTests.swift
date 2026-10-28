import AppKit
import SwiftUI
import Testing

@testable import CodeCatch
@testable import CodeCatchCore

/// A row must measure the same whether its code is concealed or revealed.
@MainActor @Suite(.serialized) struct RowLayoutTests {
    private struct RowHost: View {
        let item: CodeItem
        @Namespace private var selection
        var body: some View { CodeRow(item: item, selection: selection).frame(width: 380) }
    }

    @Test func concealedRowMeasuresLikeTheRevealedOne() async throws {
        let session = VaultSession(authenticate: {}, read: { [] }, write: { _ in }, remove: {})
        try? await session.unlock()
        AppModel.shared = AppModel(
            vaultSession: session, monitor: SourceMonitor(watchMail: { _, _ in }, hasCredential: { _ in false }),
            accounts: [])
        #expect(AppModel.shared.isUnlocked)

        let item = try #require(
            CodeItem(
                IncomingMessage(
                    text: "OTP is 343106 for txn of INR 273.00 at SWIGGY. Do not share.", senderName: "SWIGGY",
                    senderID: "AX-SWIGGY",
                    sourceKey: MessagesStore.sourceKey, sourceLabel: "Messages", date: Date(), isMail: false),
                code: "343106", link: nil))
        #expect(!item.preview.isEmpty, "the row needs a preview line for this check to mean anything")

        let saved = UserDefaults.standard.object(forKey: Prefs.blurCodes)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: Prefs.blurCodes) }
            else { UserDefaults.standard.removeObject(forKey: Prefs.blurCodes) }
        }

        let reveal = measure(item, blur: false)
        let conceal = measure(item, blur: true)

        #expect(reveal.height > 0)
        #expect(conceal.height == reveal.height)
        #expect(conceal.width == reveal.width)
    }

    /// The control: with previews off the row must be shorter.
    @Test func thePreviewLineAddsToTheRowHeight() async throws {
        let session = VaultSession(authenticate: {}, read: { [] }, write: { _ in }, remove: {})
        try? await session.unlock()
        AppModel.shared = AppModel(
            vaultSession: session, monitor: SourceMonitor(watchMail: { _, _ in }, hasCredential: { _ in false }),
            accounts: [])
        let item = try #require(
            CodeItem(
                IncomingMessage(
                    text: "OTP is 343106 for txn of INR 273.00 at SWIGGY. Do not share.", senderName: "SWIGGY",
                    senderID: "AX-SWIGGY", sourceKey: MessagesStore.sourceKey, sourceLabel: "Messages",
                    date: Date(), isMail: false),
                code: "343106", link: nil))

        let saved = UserDefaults.standard.object(forKey: Prefs.showPreviews)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: Prefs.showPreviews) }
            else { UserDefaults.standard.removeObject(forKey: Prefs.showPreviews) }
        }
        UserDefaults.standard.set(false, forKey: Prefs.blurCodes)
        UserDefaults.standard.set(false, forKey: Prefs.showPreviews)
        let withoutPreview = measure(item, blur: false)
        UserDefaults.standard.set(true, forKey: Prefs.showPreviews)
        let withPreview = measure(item, blur: false)

        #expect(withPreview.height > withoutPreview.height)
    }

    private func measure(_ item: CodeItem, blur: Bool) -> NSSize {
        UserDefaults.standard.set(blur, forKey: Prefs.blurCodes)
        let host = NSHostingView(rootView: RowHost(item: item))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }
}
