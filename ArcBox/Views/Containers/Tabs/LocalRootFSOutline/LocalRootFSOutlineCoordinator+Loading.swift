import AppKit

extension LocalRootFSOutlineCoordinator {
    func loadRootNodes() {
        generation += 1
        let currentGeneration = generation
        let rootURL = parent.rootURL
        let layers = parent.layers
        let showHidden = parent.showHiddenFiles

        rootNodes = []
        outlineView?.reloadData()
        parent.selectedPath = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let entries: [LocalFileEntry]
            if let layers {
                entries = layers.listDirectory(relativePath: "", showHiddenFiles: showHidden)
            } else {
                entries =
                    (try? FileSystemService.listDirectory(
                        at: rootURL, showHiddenFiles: showHidden)) ?? []
            }

            DispatchQueue.main.async {
                guard currentGeneration == self.generation else { return }
                self.rootNodes = entries.map { LocalFileNode(entry: $0, parent: nil) }
                self.outlineView?.reloadData()
                self.adjustColumnWidths(force: true)
                DispatchQueue.main.async {
                    self.adjustColumnWidths(force: true)
                }
            }
        }
    }

    func loadChildrenIfNeeded(for node: LocalFileNode) {
        guard node.entry.isExpandable, node.children == nil, !node.isLoading else { return }

        node.isLoading = true
        let currentGeneration = generation
        let layers = parent.layers
        let showHidden = parent.showHiddenFiles
        let url = node.entry.url

        DispatchQueue.global(qos: .userInitiated).async {
            let children: [LocalFileEntry]
            // The node carries the URL of whichever layer won it, so re-derive
            // its path relative to the stack: the merged children can come
            // from layers this node's own directory does not exist in.
            if let layers, let relativePath = layers.relativePath(forHostURL: url) {
                children = layers.listDirectory(
                    relativePath: relativePath, showHiddenFiles: showHidden)
            } else {
                children =
                    (try? FileSystemService.listDirectory(at: url, showHiddenFiles: showHidden))
                    ?? []
            }

            DispatchQueue.main.async {
                guard currentGeneration == self.generation else { return }
                node.isLoading = false
                node.children = children.map { LocalFileNode(entry: $0, parent: node) }
                self.outlineView?.reloadItem(node, reloadChildren: true)
                self.adjustColumnWidths()
                DispatchQueue.main.async {
                    self.adjustColumnWidths()
                }
            }
        }
    }

}
