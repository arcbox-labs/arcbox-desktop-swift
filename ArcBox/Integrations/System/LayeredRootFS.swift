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

    /// The merged contents of one directory, plus which layers the merge
    /// could not actually read.
    struct Listing {
        let entries: [LocalFileEntry]
        /// Indices into `layers` that hold the path but failed to list it.
        /// Their files, precedence and whiteouts are missing from `entries`,
        /// so a caller showing this listing must be able to say it is
        /// incomplete — and identifying *which* layers lets callers union
        /// failures across directories instead of undercounting them.
        let unreadableLayers: Set<Int>
    }

    /// Lists the merged contents of a directory given relative to the stack
    /// root. A layer that cannot be read is skipped rather than failing the
    /// whole listing, so a partially available export still browses — but the
    /// skip is reported rather than hidden.
    func listDirectory(relativePath: String, showHiddenFiles: Bool) -> Listing {
        var listings: [[LocalRootFSService.LayerItem]] = []
        var unreadable: Set<Int> = []

        for (index, layer) in layers.enumerated() {
            let directory = Self.resolve(relativePath, in: layer)
            do {
                listings.append(
                    try LocalRootFSService.listLayerItems(
                        at: directory, showHiddenFiles: showHiddenFiles))
            } catch {
                // Most layers carry most paths not at all, which is normal and
                // contributes nothing; a path that exists but will not open is
                // a real gap in the merge.
                if FileManager.default.fileExists(atPath: directory.path) {
                    unreadable.insert(index)
                }
            }
        }

        return Listing(entries: Self.merge(listings), unreadableLayers: unreadable)
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
