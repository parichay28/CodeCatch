import Foundation

enum Prefs {
    static let showBanner = "showHUD", autoCopy = "autoCopy", autoType = "autoType", clearClipboard = "clearClipboard"
    static let codeInMenuBar = "codeInMenuBar", sound = "sound", messages = "messagesEnabled", appleMail = "appleMailEnabled", launchAtLogin = "launchAtLogin"
    static let historyDays = "historyDays", serviceIcons = "serviceIcons"
    static let hideFromCapture = "hideFromCapture", blurCodes = "blurCodes", showPreviews = "showPreviews"
    static let clearOnLock = "clearOnLock", clearedAt = "historyClearedAt"
    static let ignoredSenders = "ignoredSenders", dismissed = "dismissedMessages", vaultImportedAt = "vaultImportedAt"
    static let notCodes = "notCodes"
    static let hotkeys = "hotkeys", welcomed = "welcomed"
    /// Never stored here: `AppModel.isOn` reads it from the Keychain, where a script can't turn it on.
    static let unlockWithMac = "unlockWithMac"

    static let receivedCodes = "receivedCodes", signInLinks = "signInLinks", resetLinks = "passwordResetLinks", bitwarden = "bitwardenEnabled"
    /// What messages are read for: with all three off, no source is watched.
    static let receiving = [receivedCodes, signInLinks, resetLinks]
    static func isReceiving(in defaults: UserDefaults = .standard) -> Bool { receiving.contains(where: defaults.bool(forKey:)) }

    static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            receivedCodes: true, signInLinks: true, resetLinks: true, bitwarden: true,
            showBanner: true, autoCopy: true, autoType: false, clearClipboard: true, codeInMenuBar: true,
            sound: false, messages: true, appleMail: false, launchAtLogin: true, historyDays: 7, serviceIcons: true,
            hideFromCapture: true, blurCodes: false, showPreviews: true, clearOnLock: false, hotkeys: true,
        ])
    }

    static func history(in defaults: UserDefaults = .standard) -> TimeInterval {
        Double(max(1, defaults.integer(forKey: historyDays))) * 86400
    }

    static subscript(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
}
