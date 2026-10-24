import SwiftUI

struct BannerCard: View {
    let id: UUID
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        if let item = model.items.first(where: { $0.id == id }) {
            CodeCard(item: item, style: .banner)
                .floatingCard()
                .contextMenu { CodeMenu(item: item) }
        } else {
            // Cleared, ignored or marked Not a Code: an empty panel would still catch clicks at the top right.
            Color.clear.frame(width: 1, height: 1).onAppear { Banner.shared.hide() }
        }
    }
}
