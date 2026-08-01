import SwiftUI

/// Column geometry for the hosted content/detail split during migration.
///
/// The toolbar reserves one section for the content column — its
/// navigation title and subtitle plus its `.primaryAction` items — ending at
/// the split-view tracking separator. AppKit will not compress that section
/// below its intrinsic width. If the column is allowed to be narrower, the
/// separator stops following the split divider and the list's toolbar buttons
/// render over the detail column instead of over the list they act on.
///
/// The section's intrinsic width is driven by the item count, not by the title
/// text (measured identical for a one-character, a 39-character and a CJK
/// title). On macOS 26: one item 212pt, two items 270pt, three items 316pt.
/// `contentMin` clears the two-item case the widest list columns ship today.
///
/// Adding a third `.primaryAction` item to any list column would exceed
/// `contentMin` — raise it alongside. The native outer split owns the sidebar
/// while this view preserves each feature's existing toolbar and sheet
/// behavior.
enum ColumnWidth {
    static let contentMin: CGFloat = 280
    static let contentIdeal: CGFloat = 320
    static let contentMax: CGFloat = 600
}

struct ContentView: View {
    @Environment(AppViewModel.self) private var appVM

    // Shared ViewModels (owned by ApplicationCoordinator, shared with the menu bar)
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(VolumesViewModel.self) private var volumesVM
    @Environment(ImagesViewModel.self) private var imagesVM
    @Environment(NetworksViewModel.self) private var networksVM

    // Feature ViewModels -- local to main window
    @State private var activityVM = ActivityViewModel()
    // Owns the Kubernetes client, refresh loop, and the pod/service models it feeds.
    @State private var k8sState = KubernetesState()
    @State private var machinesVM = MachinesViewModel()
    @State private var sandboxesVM = SandboxesViewModel()
    @State private var templatesVM = TemplatesViewModel()

    var body: some View {
        NavigationSplitView {
            // Always render `contentColumn` and vary only the numeric width
            // through the SAME flexible overload. Mixing the fixed
            // `navigationSplitViewColumnWidth(0)` overload with the flexible
            // `(min:ideal:max:)` one across sibling branches makes the column
            // width latch near 0 on navigation, collapsing the list content to
            // one-character-per-line text (Activity/Templates collapse to 0).
            //
            // `ideal` only applies on a first launch: afterwards the split
            // position is restored from the window's autosaved state, so `min`
            // is what actually guarantees toolbar alignment. See `ColumnWidth`.
            contentColumn
                .background(AppColors.background)
                .toolbarSeparator()
                .navigationSplitViewColumnWidth(
                    min: isContentColumnCollapsed ? 0 : ColumnWidth.contentMin,
                    ideal: isContentColumnCollapsed ? 0 : ColumnWidth.contentIdeal,
                    max: isContentColumnCollapsed ? 0 : ColumnWidth.contentMax
                )
        } detail: {
            detailPanel
                .background(AppColors.sidebar)
                .toolbarSeparator()
        }
    }

    /// Sections rendered full-width in the detail column collapse the content
    /// column to zero width instead of showing a list.
    private var isContentColumnCollapsed: Bool {
        appVM.currentNav == .activity || appVM.currentNav == .templates
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        switch appVM.currentNav {
        case .activity:
            // Rendered full-width in the detail column; content column collapses.
            Color.clear
                .navigationTitle("Activity")
        case .containers:
            ContainersListView()
                .environment(containersVM)
        case .volumes:
            VolumesListView()
                .environment(volumesVM)
        case .images:
            ImagesListView()
                .environment(imagesVM)
        case .networks:
            NetworksListView()
                .environment(networksVM)
        case .pods:
            PodsListView()
                .environment(k8sState)
                .environment(k8sState.podsModel)
        case .services:
            ServicesListView()
                .environment(k8sState)
                .environment(k8sState.servicesModel)
        case .machines:
            MachinesView()
                .environment(machinesVM)
        case .sandboxes:
            SandboxesListView()
                .environment(sandboxesVM)
        case .templates:
            // Rendered full-width in the detail column; content column collapses.
            Color.clear
                .navigationTitle("Templates")
        case nil:
            ContainersListView()
                .environment(containersVM)
        }
    }

    // MARK: - Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        switch appVM.currentNav {
        case .activity:
            ActivityView()
                .environment(activityVM)
        case .containers:
            ContainerDetailView()
                .environment(containersVM)
        case .volumes:
            VolumeDetailView()
                .environment(volumesVM)
        case .images:
            ImageDetailView()
                .environment(imagesVM)
        case .networks:
            NetworkDetailView()
                .environment(networksVM)
                .environment(containersVM)
        case .pods:
            PodDetailView()
                .environment(k8sState)
                .environment(k8sState.podsModel)
        case .services:
            ServiceDetailView()
                .environment(k8sState)
                .environment(k8sState.servicesModel)
        case .machines:
            MachineDetailView()
                .environment(machinesVM)
        case .sandboxes:
            SandboxDetailView()
                .environment(sandboxesVM)
        case .templates:
            TemplatesListView()
                .environment(templatesVM)
        case nil:
            ContainerDetailView()
                .environment(containersVM)
        }
    }

}
