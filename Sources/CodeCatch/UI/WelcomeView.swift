import AppKit
import SwiftUI

/// Shown once on first launch, and again from the menu: a code to try, the one
/// permission that matters, and the shortcuts. Everything here also lives in Settings.
struct WelcomeView: View {
    static let windowID = "welcome"

    @ObservedObject private var model = AppModel.shared
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.launchAtLogin) private var launchAtLogin = true
    @AppStorage(Prefs.hotkeys) private var hotkeys = true

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    CodeCatchMark().fill(.linearGradient(colors: AppBrand.colors, startPoint: .top, endPoint: .bottom))
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    Text("Welcome to \(AppBrand.name)").font(.title2.weight(.semibold))
                    Text("CodeCatch catches verification codes and sign-in links as they arrive, one click or ⌘V away. Find it in the menu bar.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("See It Work") {
                SettingRow(
                    symbol: "rectangle.inset.topright.filled", color: .blue, title: "Show a Test Code",
                    subtitle: "A banner appears at the top right, as a real code would. Click it to unlock and copy."
                ) {
                    Button("Try It") { model.showTestCode() }
                        .disabled(!model.isOn(Prefs.receivedCodes))
                }
            }
            let messages = model.status[MessagesStore.sourceKey] ?? .off
            Section {
                SettingRow(
                    symbol: SourceKind.messages.symbol, color: SourceKind.messages.color, title: "Messages",
                    subtitle: messages.needsDiskAccess
                        ? "Needs Full Disk Access: turn on CodeCatch in the list that opens."
                        : "iMessage, and SMS once Text Message Forwarding is on in your iPhone’s Messages settings", status: messages
                ) {
                    if messages.needsDiskAccess {
                        Button("Allow…") { SystemSettings.fullDiskAccess() }
                    }
                    MessagesToggle()
                }
                SettingRow(
                    symbol: SourceKind.appleMail.symbol, color: SourceKind.appleMail.color, title: "Apple Mail",
                    subtitle: "Mail app inboxes, with the same Full Disk Access",
                    status: model.status[AppleMailStore.sourceKey] ?? .off
                ) {
                    AppleMailToggle()
                }
                SettingRow(
                    symbol: SourceKind.mail.symbol, color: SourceKind.mail.color, title: "Mail Accounts and Bitwarden",
                    subtitle: "Gmail, Outlook, iCloud, other mail and Bitwarden codes"
                ) {
                    Button("Set Up…") { openSettings(at: .sources) }
                }
            } header: {
                Text("What to Catch")
            } footer: {
                if messages.needsDiskAccess {
                    Text(
                        "macOS lets apps read Messages only with Full Disk Access. CodeCatch reads Messages and Apple Mail, nothing else. "
                            + "It never changes them. Codes stay on this Mac. If you’d rather not, turn Messages off. "
                            + "Gmail, Outlook and other mail work without it."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Good to Know") {
                if hotkeys {
                    ForEach(Hotkeys.all, id: \.label) { hotkey in
                        SettingRow(symbol: "command", color: .gray, title: hotkey.title) {
                            Text(hotkey.label).monospaced().foregroundStyle(.secondary)
                        }
                    }
                }
                SettingRow(symbol: "power", color: .green, title: "Open at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LoginItem.sync(userChanged: true) }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text("Reopen it from the gear menu → Welcome Guide.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .bottomBar()
        }
        // Shorter on a small screen, where the Dock would cover the Done bar; the form scrolls.
        .frame(width: 500, height: min(740, (NSScreen.main?.visibleFrame.height ?? 740) - 40))
        .onAppear {
            UserDefaults.standard.set(true, forKey: Prefs.welcomed)
            // Next turn of the run loop: the window isn't on screen yet.
            DispatchQueue.main.async { NSApp.comeForward() }
        }
    }
}
