import Foundation

/// What a Files tab is browsing, and how much of it is missing.
///
/// Container and image tabs resolve different things — one asks the daemon
/// about a container, the other computes a layer chain from an image — but
/// from the resolved guest paths onward they behave identically, and that
/// shared half is what this owns. Keeping it in one place is not only less
/// code: the merge's soundness rules (truncate at the first layer that
/// cannot be browsed, report what is missing) have to hold for both tabs,
/// and two copies is how one of them silently stops holding.
nonisolated struct LayerStack {
    /// Merged browser for the stack, or `nil` when a single layer is browsed
    /// directly and there is nothing to merge.
    private(set) var layers: LayeredRootFS?
    /// The directory the outline browses: the top layer of the stack.
    private(set) var rootURL: URL?
    /// How many layers the daemon reported, browsable or not.
    private(set) var reportedLayers = 0
    /// Stack indices whose content is absent from what was browsed. A set so
    /// exclusions seen in different directories union rather than collapse.
    private(set) var excludedIndices: Set<Int> = []
    /// Layers dropped before the stack existed, having no index to record.
    private(set) var unbrowsableLayers = 0

    /// Layers whose content the user is not seeing.
    var missingLayers: Int { excludedIndices.count + unbrowsableLayers }

    /// Whether there is a stack worth describing. A subject with a single
    /// layer has nothing to be incomplete about.
    var describesAStack: Bool { reportedLayers > 1 }

    /// Why a stack could not be browsed at all.
    enum Unresolved: Equatable {
        /// Nothing was reported to browse.
        case noPaths
        /// The top layer is not under an exported root — a path problem.
        case outsideExport
        /// The top layer maps fine but is not there — the export is not
        /// mounted, which is a different problem with a different fix.
        case exportUnavailable
    }

    /// Resolves daemon-reported guest layer paths into a browsable stack.
    ///
    /// Runs off the main actor: resolution stats every layer, and on a
    /// wedged export each stat blocks until NFS gives up.
    static func resolve(guestPaths: [String]) async -> LayerStack {
        let resolution = await Task.detached {
            LayeredRootFS.resolveHostLayers(guestPaths: guestPaths)
        }.value

        var stack = LayerStack()
        stack.reportedLayers = guestPaths.count
        stack.unbrowsableLayers = resolution.excludedCount
        stack.rootURL = resolution.hostURLs.first
        stack.layers =
            resolution.hostURLs.count > 1 ? LayeredRootFS(layers: resolution.hostURLs) : nil
        return stack
    }

    /// Classifies a stack with no browsable top layer, so callers can say
    /// which problem the user actually has.
    static func unresolved(guestPaths: [String]) -> Unresolved {
        guard let first = guestPaths.first else { return .noPaths }
        return GuestDataMount.hostURL(forGuestPath: first) == nil
            ? .outsideExport
            : .exportUnavailable
    }

    /// Records layers a listing could not represent. Unions rather than
    /// replaces: a layer dropped once has already left holes in what the
    /// user browsed, and two directories can fail on two different layers.
    mutating func exclude(_ indices: Set<Int>) {
        excludedIndices.formUnion(indices)
    }
}
