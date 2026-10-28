import AppKit
import SwiftUI

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

enum Glass {
    /// Offscreen snapshots can't sample what's behind a window, so they use the material.
    static var useMaterial = false
}

/// Liquid Glass on macOS 26+, a vibrant material before that.
private struct GlassBackground: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !Glass.useMaterial {
            content.glassEffect(.regular, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(VisualEffect().clipShape(shape))
            .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

extension View {
    /// A card in its own borderless panel (the code banner, an agent request): glass, with room
    /// around it for the glass edge and shadow.
    func floatingCard() -> some View {
        frame(width: 356).modifier(GlassBackground()).padding(12)
    }
}
