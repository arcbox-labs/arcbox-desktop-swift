import CoreGraphics

/// Dimensions that must agree across files.
///
/// This is deliberately not an inventory of every number in the app. A size
/// earns a name here only when more than one file draws the *same* element and
/// they would visibly disagree if the numbers drifted apart — a row action that
/// no longer lines up with its neighbour, a sheet that is narrower than the one
/// before it. Sizes local to a single view stay at their call site, where they
/// are easier to read than an indirection.
enum AppMetrics {

    // MARK: - List rows

    /// Height of a row in every resource list.
    static let rowHeight: CGFloat = 44

    /// The rounded icon tile at a row's leading edge.
    static let rowIcon: CGFloat = 32

    /// Trailing row controls. `IconButton` sets it, and the progress spinners
    /// and plain glyphs that sit beside one must match or the row jitters as
    /// state changes swap them in and out.
    static let rowActionButton: CGFloat = 26

    /// The state dot beside a resource's name.
    ///
    /// The menu bar and the activity strip draw a 7pt dot and the container and
    /// machine rows a 12pt one; those are left alone rather than folded in
    /// here, since collapsing them is a visual decision and not a refactor.
    static let statusDot: CGFloat = 8

    // MARK: - Sheets

    /// Width of a create/pull sheet. `NewNetworkSheet` (640) and
    /// `MachineCreateSheet` (440) predate this and still set their own.
    static let sheetWidth: CGFloat = 480

    /// The sheet's own title bar, above the form.
    static let sheetTitleBarHeight: CGFloat = 44

    /// The close button in that title bar.
    static let sheetCloseButton: CGFloat = 24

    // MARK: - Detail views

    /// Width budget for one segment of a detail view's tab bar.
    ///
    /// `DetailTabPicker` multiplies this by the tab count instead of each view
    /// carrying a hand-tuned total. 80 is at or above every per-segment width
    /// that shipped before it (the tightest was 70, for the six-tab sandbox
    /// view, and it fit "Snapshots"), so no label loses room.
    static let detailTabSegment: CGFloat = 80

    /// The shell picker above a terminal tab.
    static let shellPickerWidth: CGFloat = 140

    // MARK: - Settings

    static let settingsPaneWidth: CGFloat = 500
    static let settingsPaneHeight: CGFloat = 600
}
