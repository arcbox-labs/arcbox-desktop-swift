import SwiftUI

/// Says how many layers a Files tab merged, and warns when some of them
/// could not be read.
///
/// A layer the `~/ArcBox` export cannot serve contributes nothing to the
/// merge, so the browser would otherwise present a partial filesystem as if
/// it were complete — files unique to that layer, and the deletions it
/// records, simply would not appear.
struct LayerMergeBadge: View {
    let total: Int
    let unavailable: Int

    /// Describes a browsed stack. Renders nothing for a subject that has a
    /// single layer, since there is nothing to be incomplete about.
    init(stack: LayerStack) {
        self.init(total: stack.reportedLayers, unavailable: stack.missingLayers)
    }

    init(total: Int, unavailable: Int) {
        self.total = total
        self.unavailable = unavailable
    }

    private var isComplete: Bool { unavailable == 0 }

    @ViewBuilder
    var body: some View {
        if total > 1 {
            badge
        }
    }

    private var badge: some View {
        HStack(spacing: 4) {
            if !isComplete {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
            }

            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(isComplete ? AppColors.textMuted : AppColors.warning)
        .fixedSize()
        .help(
            isComplete
                ? "Merged view of all \(total) filesystem layers."
                : "\(unavailable) of \(total) layers are unavailable through the ~/ArcBox export; "
                    + "files that only exist in them are missing from this view."
        )
    }

    private var label: String { Self.label(total: total, unavailable: unavailable) }

    static func label(total: Int, unavailable: Int) -> String {
        unavailable == 0
            ? "merged from \(total) layers"
            : "merged from \(total - unavailable) of \(total) layers"
    }
}
