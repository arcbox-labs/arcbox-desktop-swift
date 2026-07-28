import SwiftUI

struct LocalRootFSOutlineView: NSViewRepresentable {
    let rootURL: URL
    /// Layer stack to merge while browsing. `nil` browses `rootURL` alone —
    /// the plain single-directory case (volumes, machines, sandboxes).
    var layers: LayeredRootFS?
    let showHiddenFiles: Bool
    let reloadID: String
    @Binding var selectedPath: String?
    let onOpenURL: (URL) -> Void

    func makeCoordinator() -> LocalRootFSOutlineCoordinator {
        LocalRootFSOutlineCoordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeView()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self)
        context.coordinator.syncColumnWidthsToVisibleArea()
        context.coordinator.reloadIfNeeded()
    }
}
