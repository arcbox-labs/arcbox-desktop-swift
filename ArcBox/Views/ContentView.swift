import SwiftUI

/// Column geometry for the main three-column split.
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
/// `contentMin` — raise it alongside. Full-width destinations use a separate
/// two-column split; features keep AppKit controllers only where native tables
/// or terminals add value.
enum ColumnWidth {
    static let sidebar: CGFloat = 180
    static let contentMin: CGFloat = 280
    static let contentIdeal: CGFloat = 320
    static let contentMax: CGFloat = 600
}

struct ContentView: View {
    let onAccount: () -> Void

    @Environment(AppViewModel.self) private var appVM

    // Shared ViewModels (owned by ApplicationCoordinator, shared with the menu bar)
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(VolumesViewModel.self) private var volumesVM
    @Environment(ImagesViewModel.self) private var imagesVM
    @Environment(NetworksViewModel.self) private var networksVM
    @Environment(RunnersViewModel.self) private var runnersVM

    // Feature ViewModels -- local to main window
    @State private var activityVM = ActivityViewModel()
    // Owns the Kubernetes client, refresh loop, and the pod/service models it feeds.
    @State private var k8sState = KubernetesState()
    @State private var machinesVM = MachinesViewModel()
    @State private var sandboxesVM = SandboxesViewModel()

    @ViewBuilder
    var body: some View {
        if usesFullWidthDetail {
            NavigationSplitView {
                sidebar
            } detail: {
                detailPanel
                    .background(AppColors.sidebar)
                    .toolbarSeparator()
            }
        } else {
            threeColumnLayout
        }
    }

    private var threeColumnLayout: some View {
        NavigationSplitView {
            sidebar
        } content: {
            // `ideal` only applies on a first launch: afterwards the split
            // position is restored from the window's autosaved state, so `min`
            // is what actually guarantees toolbar alignment. See `ColumnWidth`.
            contentColumn
                .background(AppColors.background)
                .toolbarSeparator()
                .navigationSplitViewColumnWidth(
                    min: ColumnWidth.contentMin,
                    ideal: ColumnWidth.contentIdeal,
                    max: ColumnWidth.contentMax
                )
        } detail: {
            detailPanel
                .background(AppColors.sidebar)
                .toolbarSeparator()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var vm = appVM

        return List(selection: $vm.currentNav) {
            ForEach(NavItem.Section.allCases) { section in
                Section(section.rawValue.capitalized) {
                    ForEach(section.items) { item in
                        Label(item.label, systemImage: item.sfSymbol)
                            // A zero badge renders nothing, so only the runner
                            // row shows its in-flight job count.
                            .badge(item == .runner ? runnersVM.activeJobCount : 0)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Main navigation")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarAccountButton(action: onAccount)
        }
        .navigationSplitViewColumnWidth(ColumnWidth.sidebar)
    }

    /// Full-width destinations use a real two-column hierarchy. Keeping a
    /// zero-width middle pane in the three-column split leaves two internal
    /// dividers stacked beside the sidebar.
    private var usesFullWidthDetail: Bool {
        appVM.currentNav == .activity
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        switch appVM.currentNav {
        case .activity:
            // Rendered by the two-column branch.
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
        case .runner:
            RunnersView()
        case .sandboxes:
            SandboxesListView()
                .environment(sandboxesVM)
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
        case .runner:
            // Job / host detail arrives with RUN-12 / RUN-13.
            ContentUnavailableView("No Selection", systemImage: "square.dashed")
        case .sandboxes:
            SandboxDetailView()
                .environment(sandboxesVM)
        case nil:
            ContainerDetailView()
                .environment(containersVM)
        }
    }
}
