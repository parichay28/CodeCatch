import AppKit
import SwiftUI

/// Capsule actions with explicit colours, so they look the same in the
/// never-key banner panel as in a key window (system styles grey out there).
struct ActionButtonStyle: ButtonStyle {
    var prominent = false
    /// A list row's button: one width for a 6-digit code, Open and Unlock alike, so the rows'
    /// pills line up locked or not. Longer titles grow it.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.medium) : .body.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .frame(minWidth: compact ? 70 : nil, maxWidth: compact ? nil : .infinity, minHeight: compact ? 24 : 30)
            .padding(.horizontal, 10)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                Capsule().fill(prominent ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.primary.opacity(0.08)))
                Capsule().strokeBorder(.primary.opacity(prominent ? 0 : 0.06), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension Color {
    /// The fill behind whatever the pointer is over, the same strength everywhere.
    static func hoverFill(_ hovering: Bool, resting: Double = 0) -> Color { .primary.opacity(hovering ? 0.08 : resting) }
}

private struct HoverHighlight<S: Shape>: ViewModifier {
    let shape: S
    let outset: CGFloat
    @Local private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Color.hoverFill(hovering)).padding(-outset))
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Highlights the view in `shape` while the pointer is over it; `outset` grows the highlight past the view.
    func hoverHighlight(in shape: some Shape, outset: CGFloat = 0) -> some View {
        modifier(HoverHighlight(shape: shape, outset: outset))
    }
}

/// Hover eases in and ends at once, so a pointer sweeping down a list leaves no fading trail.
@MainActor func hoverAnimation(_ on: Bool) -> Animation? { on ? .easeOut(duration: 0.12) : nil }

/// A toolbar-weight glyph: the face of GlyphButton and GlyphMenu.
struct GlyphLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 24, height: 24)
    }
}

/// Toolbar-weight glyph button that only shows a background on hover.
struct GlyphButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlyphLabel(symbol: symbol)
                .hoverHighlight(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// GlyphButton's twin for a menu: the same glyph, the same hover circle.
struct GlyphMenu<Content: View>: View {
    let symbol: String
    let help: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) { GlyphLabel(symbol: symbol) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24, height: 24)
            .hoverHighlight(in: Circle())
            .help(help)
            .accessibilityLabel(help)
    }
}

/// The title and the line under it at the top of a sheet.
struct SheetHeader: View {
    let title: String
    let about: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            Text(about).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// An error or warning, drawn the same everywhere: orange, with a warning sign. The caller
/// sets the font. `compact` keeps it to one line, with the full text on hover.
struct WarningText: View {
    let message: String
    var compact = false
    /// Worth knowing, not a warning.
    var calm = false

    var body: some View {
        Label(message, systemImage: calm ? "info.circle" : "exclamationmark.triangle.fill")
            .foregroundStyle(calm ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            .lineLimit(compact ? 1 : nil)
            .fixedSize(horizontal: false, vertical: !compact)
            .help(compact ? message : "")
    }
}

/// Unlock, showing the same busy state wherever it is while Touch ID or the password is up.
struct VaultUnlockButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isBusy ? "Unlocking…" : "Unlock", systemImage: "lock.fill")
        }
        .disabled(isBusy)
    }
}

extension View {
    /// The strip along the bottom of the Settings, Welcome and Recent Emails windows.
    func bottomBar() -> some View {
        padding(.horizontal, 20).padding(.vertical, 10).background(.background).overlay(alignment: .top) { Divider() }
    }

    /// The faint rounded box behind a list or group in Settings; clipped so the end rows' hover stays inside the corners.
    func well(cornerRadius: CGFloat = 12) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.primary.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
