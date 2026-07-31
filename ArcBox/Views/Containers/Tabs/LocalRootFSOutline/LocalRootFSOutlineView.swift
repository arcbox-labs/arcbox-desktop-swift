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
    /// Reports, per listing, which layers held the directory but could not
    /// be read — a layer that dies after the tab loaded shows up here and
    /// nowhere else, so the caller can keep its "incomplete" warning honest.
    /// Identifying the layers lets the caller union failures across
    /// directories; a bare count would collapse distinct layers into one.
    var onUnreadableLayers: ((Set<Int>) -> Void)?

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
