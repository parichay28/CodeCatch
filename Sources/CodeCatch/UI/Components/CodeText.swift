import AppKit
import SwiftUI

/// "482 913" / "4829 1365": halves split by a thin space, like Passwords shows them.
func groupedCode(_ code: String, wide: Bool = false) -> String {
    guard code.count >= 6, code.count.isMultiple(of: 2), code.allSatisfy(\.isNumber) else { return code }
    return code.prefix(code.count / 2) + (wide ? "\u{2002}" : "\u{2009}") + code.suffix(code.count / 2)
}

/// Stands in for a code while the app is locked, so the digits are in no view or accessibility tree.
func hiddenCode(_ code: String) -> String { String(repeating: "•", count: code.count) }

/// A code as cards and rows draw it: SF Pro with tabular figures, open tracking.
struct CodeText: View {
    let code: String
    var size: CGFloat = 38
    var weight: Font.Weight = .semibold
    var concealed = false

    /// Wide enough that no digit survives, whatever the point size.
    private var blurRadius: CGFloat { max(4, size * 0.2) }

    private var text: some View {
        Text(groupedCode(code, wide: true))
            .font(.system(size: size, weight: weight).monospacedDigit())
            .tracking(size * 0.05)
            .lineLimit(1)
            // Never shrunk to fit: a fitting pass animates the glyph scale, which read as the code
            // zooming inside a still pill. The glyphs keep one size; the capsule grows around them.
            .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        // Two copies, one sharp and one blurred. The sharp one is always laid out, so revealing the
        // code cannot change the text's width, and only opacity animates: animating the blur radius
        // re-rasterises the text every frame, which is what made hovering stutter.
        text
            .opacity(concealed ? 0 : 1)
            .overlay {
                if concealed {
                    text.blur(radius: blurRadius).accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.12), value: concealed)
            .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
    }
}
