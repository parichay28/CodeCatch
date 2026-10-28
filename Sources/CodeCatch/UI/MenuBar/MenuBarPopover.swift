import AppKit

/// Opens the menu-bar popover from a shortcut or a codecatch://search link, as if its
/// icon were clicked (SwiftUI's MenuBarExtra has no API for it).
@MainActor
enum MenuBarPopover {
    static var isOpen: Bool {
        NSApp.windows.contains { $0.className.contains("MenuBarExtraWindow") && $0.isVisible }
    }

    /// `query: nil` keeps the current search. `retries`: a codecatch:// link can launch the app
    /// and arrive before the status item exists.
    static func open(query: String? = "", retries: Int = 10) {
        if let query { AppModel.shared.searchRequest = query }
        guard !isOpen else { return }
        guard let statusItem = Self.statusItem else {
            if retries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { open(query: query, retries: retries - 1) } }
            return
        }
        NSApp.activate()
        // macOS 27+: SwiftUI shows the window when AppKit begins an "expanded interface session"
        // (SPI; the button has no target/action any more). Its timestamp argument debounces
        // re-opening; the largest one always passes. Earlier macOS: click the button.
        let begin = NSSelectorFromString("_beginExpandedInterfaceSession:")
        if statusItem.responds(to: begin), let implementation = statusItem.method(for: begin) {
            typealias Begin = @convention(c) (NSStatusItem, Selector, TimeInterval) -> Void
            unsafeBitCast(implementation, to: Begin.self)(statusItem, begin, .greatestFiniteMagnitude)
        } else {
            statusItem.button?.performClick(nil)
        }
    }

    /// Closes the popover after an action that opens a window. macOS 27 otherwise keeps it
    /// open on top of that window until the next click; earlier macOS closes it by itself.
    static func close() {
        // `expandedInterfaceSession?.cancel()`, public in the macOS 27 SDK: by name, as CI builds with an older one.
        let session = "expandedInterfaceSession"
        if let statusItem, statusItem.responds(to: NSSelectorFromString(session)) {
            (statusItem.value(forKey: session) as? NSObject)?.perform(NSSelectorFromString("cancel"))
            return
        }
        // macOS 15–26 have no session to cancel, and do not always close the popover for another
        // window. Dismiss it the way Escape does, so the status item's idea of "open" stays in step;
        // ordering the window out behind its back can leave the next click doing nothing.
        guard let window = NSApp.windows.first(where: { $0.className.contains("MenuBarExtraWindow") && $0.isVisible })
        else { return }
        if let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53)
        {
            window.sendEvent(escape)
        }
        if window.isVisible { window.orderOut(nil) }
    }

    // Only the status bar window has this key; asking any other window raises.
    private static var statusItem: NSStatusItem? {
        NSApp.windows.lazy.filter { $0.className == "NSStatusBarWindow" && $0.responds(to: NSSelectorFromString("statusItem")) }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }.first
    }

    /// `codecatch://search?q=github`: for launchers (a Raycast or Alfred quicklink).
    static func handle(_ url: URL) {
        guard url.scheme == "codecatch" else { return }
        open(query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? "")
    }
}
