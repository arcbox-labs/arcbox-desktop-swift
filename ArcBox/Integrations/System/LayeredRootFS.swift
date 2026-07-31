import Foundation

/// Browses an overlay layer stack as one merged filesystem.
///
/// Containers and images under the containerd image store are not a single
/// directory: the daemon resolves them to the same layer list the kernel
/// would mount — a writable upper layer (containers only) followed by the
/// image layers, highest first. The read-only `~/ArcBox` export serves each
/// layer directory separately, so composing them here is what turns "the
/// container's own writes" into "the container's filesystem".
///
/// This is a client-side union, not an overlayfs mount, and it reproduces
/// overlay precedence and whiteouts but not opaque directories: those are
/// recorded in a `trusted.overlay.*` xattr that does not survive the NFS
/// export, so a directory the upper layer replaced wholesale still shows the
/// entries it shadowed. A kernel-composed view (ABX-424) removes that caveat.
nonisolated struct LayeredRootFS {
    /// Layer directories, highest precedence first — the order overlayfs
    /// encodes as `upperdir` then `lowerdir=A:B:C`.
    let layers: [URL]

    init?(layers: [URL]) {
        guard !layers.isEmpty else { return nil }
        self.layers = layers
    }

    /// Whether composing is worth it at all: one layer merges to itself.
    var isComposed: Bool { layers.count > 1 }

    /// The merged contents of one directory, plus which layers are missing
    /// from it.
    struct Listing {
        let entries: [LocalFileEntry]
        /// Indices into `layers` whose content is not represented in
        /// `entries`: the layer that failed to list, and — because its
        /// whiteouts and replacements are unknowable — everything beneath
        /// it. A caller showing this listing must be able to say it is
        /// incomplete; identifying *which* layers lets callers union
        /// failures across directories instead of undercounting them.
        let excludedLayers: Set<Int>
    }

    /// Lists the merged contents of a directory given relative to the stack
    /// root.
    ///
    /// A layer that cannot be read truncates the stack rather than being
    /// skipped over. Skipping would let entries from lower layers surface
    /// even though the unreadable layer may delete or replace them — showing
    /// files the container or image does not actually have, which is worse
    /// than showing fewer. Everything *above* the failure is unaffected:
    /// lower layers can never override it. So the listing stays sound and
    /// merely loses depth, and the loss is reported.
    func listDirectory(relativePath: String, showHiddenFiles: Bool) -> Listing {
        var listings: [[LocalRootFSService.LayerItem]] = []
        var excluded: Set<Int> = []

        for (index, layer) in layers.enumerated() {
            let directory = Self.resolve(relativePath, in: layer)
            do {
                listings.append(
                    try LocalRootFSService.listLayerItems(
                        at: directory, showHiddenFiles: showHiddenFiles))
            } catch {
                // A layer that is present but simply lacks this path holds no
                // opinion about it — a whiteout would have to live inside that
                // very directory — so it is normal and the merge continues.
                // A layer that is missing outright is unavailable, and its
                // whiteouts are as unknowable as an unreadable one's.
                let layerPresent = FileManager.default.fileExists(atPath: layer.path)
                let pathPresent = FileManager.default.fileExists(atPath: directory.path)
                if layerPresent && !pathPresent {
                    continue
                }
                excluded.formUnion(index..<layers.count)
                break
            }
        }

        return Listing(entries: Self.merge(listings), excludedLayers: excluded)
    }

    /// Layer paths mapped onto the export, and how many were left behind.
    struct Resolution {
        /// Host URLs for the layers that can be browsed, highest first.
        let hostURLs: [URL]
        /// Layers dropped from the tail, either unmappable or absent on the
        /// host. Never represented in the merge, so a caller must count them
        /// against the view's completeness.
        let excludedCount: Int
    }

    /// Maps daemon-reported guest layer paths onto the `~/ArcBox` export,
    /// stopping at the first layer the host cannot browse.
    ///
    /// Truncating rather than dropping matters for the same reason it does
    /// inside [`listDirectory`]: a layer that cannot be browsed still decides
    /// what the layers beneath it may show, so merging past it would surface
    /// entries it may replace or delete.
    static func resolveHostLayers(guestPaths: [String]) -> Resolution {
        var hostURLs: [URL] = []
        for guestPath in guestPaths {
            guard let hostURL = GuestDataMount.hostURL(forGuestPath: guestPath),
                (try? LocalRootFSService.resolveRootURL(path: hostURL.path)) != nil
            else {
                break
            }
            hostURLs.append(hostURL)
        }
        return Resolution(
            hostURLs: hostURLs,
            excludedCount: guestPaths.count - hostURLs.count
        )
    }

    /// Maps a host URL that came out of [`listDirectory`] back to its path
    /// relative to the stack root, so expanding a node can re-merge across
    /// every layer rather than only the one the node happened to come from.
    func relativePath(forHostURL url: URL) -> String? {
        let path = url.standardizedFileURL.path
        for layer in layers {
            let base = layer.standardizedFileURL.path
            if path == base {
                return ""
            }
            if path.hasPrefix(base + "/") {
                return String(path.dropFirst(base.count + 1))
            }
        }
        return nil
    }

    /// Merges per-layer listings, highest layer first.
    ///
    /// The first layer to name an entry decides it: a regular entry is taken
    /// as-is, a whiteout deletes the name for every layer below (and is
    /// itself hidden, being overlay bookkeeping rather than content).
    static func merge(_ listings: [[LocalRootFSService.LayerItem]]) -> [LocalFileEntry] {
        var decided: Set<String> = []
        var merged: [LocalFileEntry] = []

        for listing in listings {
            for item in listing {
                guard decided.insert(item.entry.name).inserted else { continue }
                if !item.isWhiteout {
                    merged.append(item.entry)
                }
            }
        }

        return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func resolve(_ relativePath: String, in layer: URL) -> URL {
        relativePath.isEmpty ? layer : layer.appendingPathComponent(relativePath)
    }
}
