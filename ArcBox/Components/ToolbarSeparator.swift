import SwiftUI

extension View {
    /// Gives a `NavigationSplitView` column the 1pt rule under the window
    /// toolbar that it would otherwise show only some of the time.
    ///
    /// macOS 26 separates the toolbar from each split-view pane with a scroll
    /// pocket and picks the style per pane: a pane whose root is a scroll view
    /// gets the soft scroll-edge fade, a pane without one gets the hard rule.
    /// ArcBox's list column scrolls and its detail column mostly does not, so
    /// the rule appeared over one column and not its neighbour. AppKit also
    /// forces the hard rule onto every pane while a toolbar section is too wide
    /// for its column, which is why the rule used to reappear once the content
    /// column was dragged below its toolbar section — see `ColumnWidth`.
    ///
    /// A top safe-area inset takes the scroll view off the pane root, so AppKit
    /// draws the rule for this column unconditionally. That keeps it native —
    /// same 1pt, same colour, same position as every other pane's — rather than
    /// drawing a second rule 1pt below AppKit's. The inset is deliberately empty
    /// and zero-height: it changes nothing about layout, only that decision.
    ///
    /// Not covered by a test: the column is only scroll-backed once its list has
    /// loaded, and the unit-test host has no daemon, so the case never arises
    /// there. Verify by eye after changing this — the rule has to run unbroken
    /// from the sidebar edge to the window edge at any split position.
    func toolbarSeparator() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0)
        }
    }
}
