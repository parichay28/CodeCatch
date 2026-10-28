import AppKit
import Testing

@testable import CodeCatch
@testable import CodeCatchCore

/// The privacy switch over `Clipboard.copy`: by default a copy is marked so clipboard managers skip it;
/// with the setting on, it is a normal copy that history tools may record.
@Suite(.serialized) struct ClipboardHistoryTests {
    private let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    @Test func copiesAreHiddenFromClipboardManagersByDefault() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        Clipboard.copy("482913", pasteboard: pasteboard, history: false)

        #expect(pasteboard.string(forType: .string) == "482913")
        #expect(pasteboard.types?.contains(concealed) == true)
        #expect(pasteboard.types?.contains(transient) == true)
    }

    @Test func copiesAreRecordedWhenTheSettingIsOn() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        Clipboard.copy("482913", pasteboard: pasteboard, history: true)

        #expect(pasteboard.string(forType: .string) == "482913")
        #expect(pasteboard.types?.contains(concealed) == false)
        #expect(pasteboard.types?.contains(transient) == false)
    }
}
