import CodeCatchCore
import SwiftUI

/// Settings → Sources → Not a Code: the kinds of message no code is read from, with − to read them again.
struct NotCodesSheet: View {
    @ObservedObject private var model = AppModel.shared
    @Local private var selection = Set<String>()

    var body: some View {
        ListSheet(
            title: "Not a Code",
            about: "CodeCatch reads no code from messages like these. Their sender's other codes still come through. "
                + "To add one, right-click a wrongly caught code and choose Not a Code."
        ) {
            List(selection: $selection) {
                ForEach(model.notCodes.reversed()) { NotCodeRow(rule: $0) }
            }
            .contextMenu(forSelectionType: String.self) { picked in
                Button("Read Codes Again") { forget(picked) }
            }
            .onDeleteCommand { forget(selection) }
            .overlay {
                if model.notCodes.isEmpty {
                    ContentUnavailableView(
                        "Nothing Marked", systemImage: "xmark.seal",
                        description: Text("Right-click a wrongly caught code and choose Not a Code."))
                }
            }
        } bar: {
            HStack(spacing: 0) {
                Button {
                    forget(selection)
                } label: {
                    Image(systemName: "minus").frame(width: 24, height: 22)
                }
                .help("Read codes from the selected messages again")
                .accessibilityLabel("Read codes again")
                .disabled(selection.isEmpty)
                Spacer()
            }
            .padding(4)
        }
    }

    private func forget(_ picked: Set<String>) {
        guard !picked.isEmpty else { return }
        model.forgetNotCodes(picked)
        selection.subtract(picked)
    }
}

/// Which messages a rule covers: their sender, with its logo, and when it was marked.
private struct NotCodeRow: View {
    let rule: NotCodeRule
    @ObservedObject private var icons = IconStore.shared

    var body: some View {
        let isMail = rule.sender.contains("@")
        let name = ServiceIdentity.name(senderName: "", senderAddress: rule.sender, isMail: isMail, text: "")
        let domain = ServiceIdentity.domain(senderAddress: rule.sender, isMail: isMail, text: "", service: name)
        HStack(spacing: 10) {
            Group {
                if let icon = icons.icon(for: domain) { LogoTile(icon: icon, size: 28) } else { Monogram(name: name, size: 28) }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                Text("\(rule.sender) · \(rule.added.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
