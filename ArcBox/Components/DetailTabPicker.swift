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
/// The pre-Tahoe fallback width follows from the tab count. Each detail view
/// used to carry its own total — 120 through 420 across eight views, fitted by
/// eye and with no consistent width per segment — so adding a tab meant
/// re-tuning a number that gave no hint it needed re-tuning.
struct DetailTabPicker<Tab: DetailTab>: ToolbarContent {
    @Binding var selection: Tab

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                LiquidGlassDetailTabPicker(selection: $selection)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
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
                            .padding(.horizontal, 12)
                            .frame(height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
            .frame(minWidth: AppMetrics.detailTabSegment)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
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
