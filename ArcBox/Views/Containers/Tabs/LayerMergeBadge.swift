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

    private var isComplete: Bool { unavailable == 0 }

    var body: some View {
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

    private var label: String {
        isComplete
            ? "merged from \(total) layers"
            : "merged from \(total - unavailable) of \(total) layers"
    }
}
