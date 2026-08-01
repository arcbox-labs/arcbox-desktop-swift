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
/// The width follows the tab count with a three-segment floor, so single-tab
/// detail views keep the same toolbar presence instead of collapsing to a chip.
struct DetailTabPicker<Tab: DetailTab>: ToolbarContent {
    @Binding var selection: Tab

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                LiquidGlassDetailTabPicker(selection: $selection)
            }
            .sharedBackgroundVisibility(.visible)
        } else {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $selection) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(
                    minWidth: DetailTabLayout.minimumWidth(for: Tab.allCases.count),
                    idealWidth: DetailTabLayout.idealWidth(for: Tab.allCases.count),
                    maxWidth: DetailTabLayout.idealWidth(for: Tab.allCases.count)
                )
            }
        }
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassDetailTabPicker<Tab: DetailTab>: View {
    @Binding var selection: Tab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(
            spacing: CGFloat(Tab.allCases.count) * AppMetrics.detailTabSegment
        ) {
            HStack(spacing: 2) {
                ForEach(Tab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .frame(minWidth: 44, maxWidth: .infinity)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selection == tab ? .primary : .secondary)
                    .glassEffect(
                        selection == tab ? .regular.interactive() : .identity
                    )
                    .glassEffectID(
                        selection == tab ? "selected-detail-tab" : nil,
                        in: glassNamespace
                    )
                }
            }
            .padding(2)
        }
        .frame(
            minWidth: DetailTabLayout.minimumWidth(for: Tab.allCases.count),
            idealWidth: DetailTabLayout.idealWidth(for: Tab.allCases.count),
            maxWidth: DetailTabLayout.idealWidth(for: Tab.allCases.count)
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.3),
            value: selection
        )
        .accessibilityRepresentation {
            Picker("Tab", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private enum DetailTabLayout {
    static func minimumWidth(for count: Int) -> CGFloat {
        count <= 2
            ? 3 * AppMetrics.detailTabSegment
            : CGFloat(count) * AppMetrics.detailTabSegment * 0.7
    }

    static func idealWidth(for count: Int) -> CGFloat {
        CGFloat(max(count, 3)) * AppMetrics.detailTabSegment
    }
}
