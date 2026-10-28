import AppKit
import SwiftUI

struct SourcesTab: View {
    @ObservedObject private var model = AppModel.shared
    @AppStorage(Prefs.messages) private var messagesEnabled = true
    @AppStorage(Prefs.appleMail) private var appleMailEnabled = false
    @Local private var editing: MailAccount?
    @Local private var adding = false
    @Local private var ignoring = false
    @Local private var notCoding = false
    #if DEBUG
        @Local private var importResult: String?
    #endif
    @Local private var bitwarden = false
    @Local private var vaultError: String?

    var body: some View {
        Form {
            Section {
                SettingRow(
                    symbol: CatchKind.code.symbol, color: CatchKind.code.color, title: "Verification Codes",
                    info: "Read from Messages and mail. Turning this off stops reading Messages. Turning it back on reads recent history again.",
                    isOn: setting(Prefs.receivedCodes))
                SettingRow(
                    symbol: CatchKind.signIn.symbol, color: CatchKind.signIn.color, title: "Sign-In Links",
                    info: "Read from mail. Links open only when you click them, after you unlock CodeCatch.",
                    isOn: setting(Prefs.signInLinks))
                SettingRow(
                    symbol: CatchKind.passwordReset.symbol, color: CatchKind.passwordReset.color, title: "Password Reset Links",
                    info: "Links to reset or change a password, read from mail. Links open only when you click them, after you unlock CodeCatch.",
                    isOn: setting(Prefs.resetLinks))
                SettingRow(
                    symbol: "nosign", color: .gray, title: "Ignored Senders", subtitle: ignoredSummary,
                    info: "Codes and links from these senders are skipped. To ignore a sender, right-click one of their codes."
                ) {
                    Button("Edit…") { ignoring = true }
                }
                SettingRow(
                    symbol: "xmark.seal", color: .gray, title: "Not a Code", subtitle: notCodeSummary,
                    info: "No code is read from messages like these. Their sender's other codes still come through. "
                        + "To add one, right-click a wrongly caught code and choose Not a Code."
                ) {
                    Button("Edit…") { notCoding = true }
                }
            } header: {
                Text("What to Catch")
            } footer: {
                if !model.receiving {
                    Text("Messages and mail are paused.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Messages") {
                let status = model.status[MessagesStore.sourceKey] ?? .off
                let codes = model.isOn(Prefs.receivedCodes)
                let about =
                    "Reads codes from iMessage and SMS on this Mac. For SMS, turn on Text Message Forwarding in your iPhone’s Messages settings. Needs Full Disk Access, the only way macOS lets apps read Messages."
                SettingRow(
                    symbol: SourceKind.messages.symbol, color: SourceKind.messages.color, title: "Messages",
                    subtitle: codes ? problem(status) : "Paused while Verification Codes is off", info: about, status: status,
                    details: sourceDetails(MessagesStore.sourceKey, about: about, enabled: messagesEnabled && codes)
                ) {
                    MessagesToggle()
                }
                if messagesEnabled { diskAccessRow(status) }
            }

            Section("Mail") {
                let appleMail = model.status[AppleMailStore.sourceKey] ?? .off
                let aboutMail =
                    "Reads new mail in the Mail app on this Mac, with no sign-in. Nothing is changed or marked as read. Mail fetches new mail only while it is open. Needs Full Disk Access, which macOS requires to read Mail’s files."
                SettingRow(
                    symbol: SourceKind.appleMail.symbol, color: SourceKind.appleMail.color, title: "Apple Mail", subtitle: problem(appleMail), info: aboutMail,
                    status: appleMail,
                    details: sourceDetails(AppleMailStore.sourceKey, about: aboutMail, enabled: appleMailEnabled && model.receiving)
                ) {
                    AppleMailToggle()
                }
                if appleMailEnabled { diskAccessRow(appleMail) }
                ForEach(model.accounts) { account in
                    let status = model.status[account.id.uuidString] ?? .off
                    let about = "Nothing is changed or marked as read. Your \(account.usesSignIn ? "sign-in" : "password") stays in your Keychain."
                    SettingRow(
                        symbol: SourceKind.mail.symbol, color: account.isGmail ? .red : SourceKind.mail.color,
                        title: account.label, subtitle: [account.user, problem(status)].compactMap { $0 }.joined(separator: " · "),
                        info: about, status: status,
                        details: sourceDetails(account.id.uuidString, about: about, enabled: account.enabled && model.receiving) { editing = account }
                    ) {
                        Toggle(
                            "Watch \(account.label)",
                            isOn: Binding(
                                get: { account.enabled },
                                set: { enabled in
                                    var updated = account
                                    updated.enabled = enabled
                                    model.save(updated)
                                })
                        ).labelsHidden()
                    }
                    .contextMenu {
                        Button("Edit Account…") { editing = account }
                        Button("Check Now") { model.monitor.check(account.id.uuidString) }
                            .disabled(!(account.enabled && model.receiving))
                    }
                }
                HStack {
                    #if DEBUG
                        Menu {
                            Button("Add Mail Account…") { adding = true }
                            Button("Import from .env…", action: importEnv)
                        } label: {
                            Text("Add Account…")
                        } primaryAction: {
                            adding = true
                        }
                        .fixedSize()
                        Spacer()
                        if let importResult { Text(importResult).font(.caption).foregroundStyle(.secondary) }
                    #else
                        Button("Add Account…") { adding = true }
                        Spacer()
                    #endif
                }
            }

            Section("Bitwarden") {
                SettingRow(
                    symbol: "key.fill", color: .blue, title: "Bitwarden", subtitle: vaultSubtitle,
                    info: aboutBitwarden, details: model.hasVault ? bitwardenDetails : nil
                ) {
                    if model.hasVault {
                        Toggle("Bitwarden", isOn: setting(Prefs.bitwarden)).labelsHidden()
                    } else {
                        Button("Set Up…") {
                            model.set(Prefs.bitwarden, on: true)
                            bitwarden = true
                        }
                    }
                }
                if let error = vaultError ?? (model.isUnlocked ? nil : model.unlockError) {
                    WarningText(message: error).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { AccountEditor(account: $0) }
        .sheet(isPresented: $bitwarden) { BitwardenSheet() }
        .sheet(isPresented: $adding) { AddAccountSheet { editing = $0 } }
        .sheet(isPresented: $ignoring) { IgnoredSendersSheet() }
        .sheet(isPresented: $notCoding) { NotCodesSheet() }
        .onReceive(model.$editAccountRequest) { id in
            guard let id else { return }
            model.editAccountRequest = nil
            editing = model.accounts.first { $0.id == id }
        }
    }

    private var ignoredSummary: String {
        switch model.ignoredSenders.count {
        case 0: "None"
        case 1: "1 sender"
        case let count: "\(count) senders"
        }
    }

    private var notCodeSummary: String {
        switch model.notCodes.count {
        case 0: "None"
        case 1: "1 kind of message"
        case let count: "\(count) kinds of message"
        }
    }

    private var aboutBitwarden: String {
        let shown =
            model.isOn(Prefs.unlockWithMac)
            ? "show whenever your Mac is unlocked"
            : "stay hidden until you unlock with \(DeviceAuthentication.unlockMethods)"
        let about = "Shows Bitwarden codes for your saved logins. Codes are made on this Mac and \(shown)."
        return model.hasVault ? about + " Turning this off hides the codes and keeps them saved. It also locks CodeCatch." : about
    }

    private var bitwardenDetails: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text(aboutBitwarden).foregroundStyle(.secondary)
                Divider()
                HStack {
                    PopoverButton("Refresh…") { bitwarden = true }
                        .disabled(!model.isOn(Prefs.bitwarden))
                    if model.vaultSession.isUnlocked {
                        Button("Lock") {
                            vaultError = nil
                            model.vaultSession.lock()
                        }
                    } else {
                        VaultUnlockButton(isBusy: model.vaultSession.isBusy) {
                            vaultError = nil
                            model.unlocked {}
                        }
                        .disabled(!model.isOn(Prefs.bitwarden))
                    }
                    Spacer()
                    PopoverButton("Remove Bitwarden Codes…", role: .destructive) {
                        vaultError = nil
                        guard
                            confirmed(
                                "Remove Bitwarden codes?",
                                "CodeCatch forgets the logins it imported. Your Bitwarden vault doesn't change. To get them back, import again.",
                                action: "Remove")
                        else { return }
                        Task {
                            do { try await model.removeVault() } catch { if !AppModel.isCancel(error) { vaultError = error.localizedDescription } }
                        }
                    }.disabled(model.vaultSession.isBusy)
                }
            })
    }

    private var vaultSubtitle: String? {
        guard model.hasVault else { return nil }
        guard model.isOn(Prefs.bitwarden) else { return "Off · codes kept" }
        let state = model.vaultSession.isUnlocked ? "\(model.vault.count) codes" : "Locked"
        guard let imported = UserDefaults.standard.object(forKey: Prefs.vaultImportedAt) as? Date else { return state }
        return state + " · imported " + imported.formatted(.relative(presentation: .named))
    }

    private func setting(_ key: String) -> Binding<Bool> {
        Binding(get: { model.isOn(key) }, set: { model.set(key, on: $0) })
    }

    @ViewBuilder private func diskAccessRow(_ status: SourceStatus) -> some View {
        if status.needsDiskAccess {
            SettingRow(
                symbol: "lock.shield.fill", color: .orange, title: "Full Disk Access Needed",
                subtitle: "Used only to read Messages and Apple Mail. Turn on CodeCatch in the list that opens."
            ) {
                Button("Allow…") { SystemSettings.fullDiskAccess() }
            }
        }
    }

    /// What is wrong, when something is. Missing Full Disk Access has its own row.
    private func problem(_ status: SourceStatus) -> String? {
        status.needsAttention && !status.needsDiskAccess ? status.summary : nil
    }

    /// The source's health and actions, shown when its row is clicked.
    private func sourceDetails(_ key: String, about: String, enabled: Bool, edit: (() -> Void)? = nil) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                SourceBadge(status: model.status[key] ?? .off)
                Text(about).foregroundStyle(.secondary)
                Divider()
                SourceHealthDetails(health: model.monitor.health[key] ?? SourceHealth(), now: model.now)
                HStack {
                    Button("Check Now") { model.monitor.check(key) }.disabled(!enabled)
                    if let edit { PopoverButton("Edit Account…", action: edit) }
                }
            })
    }

    #if DEBUG
        private func importEnv() {
            let panel = NSOpenPanel()
            panel.showsHiddenFiles = true
            panel.message = "Choose a .env file with *_USER / *_PASS pairs"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            var accounts = model.accounts
            do {
                let n = try EnvImport.importCredentials(from: url.path, into: &accounts)
                model.accounts = accounts
                importResult = n == 1 ? "Imported 1 password" : "Imported \(n) passwords"
            } catch {
                importResult = error.localizedDescription
            }
        }
    #endif
}

/// Messages on or off, restarting its watcher on change. Shared by Welcome and Settings → Sources.
struct MessagesToggle: View {
    @AppStorage(Prefs.messages) private var enabled = true

    var body: some View {
        Toggle("Messages", isOn: $enabled).labelsHidden()
            .onChange(of: enabled) { AppModel.shared.restartMessages() }
    }
}

/// Apple Mail on or off, restarting its watcher on change. Shared by Welcome and Settings → Sources.
struct AppleMailToggle: View {
    @AppStorage(Prefs.appleMail) private var enabled = false

    var body: some View {
        Toggle("Apple Mail", isOn: $enabled).labelsHidden()
            .onChange(of: enabled) { AppModel.shared.restartAppleMail() }
    }
}
