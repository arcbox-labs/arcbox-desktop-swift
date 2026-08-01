import SwiftUI

/// The tab set of a detail view.
///
/// Every conforming enum already satisfies each requirement; the protocol
/// exists so `DetailTabPicker` can name them in one place.
///
/// Conformers write `@MainActor DetailTab`. The target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, so each enum's hand-written
/// `Identifiable` conformance is main-actor isolated, and a conformance that
/// depends on it has to say so.
protocol DetailTab: CaseIterable, Identifiable, Hashable, RawRepresentable
where RawValue == String, AllCases: RandomAccessCollection {}

/// The segmented tab bar in a detail view's toolbar.
///
/// The width follows from the tab count. Each detail view used to carry its own
/// total — 120 through 420 across eight views, fitted by eye and with no
/// consistent width per segment — so adding a tab meant re-tuning a number that
/// gave no hint it needed re-tuning.
struct DetailTabPicker<Tab: DetailTab>: ToolbarContent {
    @Binding var selection: Tab

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Tab", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(
                minWidth: AppMetrics.detailTabSegment,
                maxWidth: CGFloat(Tab.allCases.count) * AppMetrics.detailTabSegment
            )
        }
    }
}
