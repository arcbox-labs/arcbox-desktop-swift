import ArcBoxClient
import SwiftUI

/// Column geometry for the main window's three-column layout.
///
/// The window toolbar reserves one section for the content column — its
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
/// `contentMin` — raise it alongside, and let
/// `ContentViewColumnLayoutTests` confirm the new value.
enum ColumnWidth {
    static let sidebar: CGFloat = 180
    static let contentMin: CGFloat = 280
    static let contentIdeal: CGFloat = 320
    static let contentMax: CGFloat = 600
}

struct ContentView: View {
    @Environment(AppViewModel.self) private var appVM

    // Shared ViewModels (injected from ArcBoxApp, shared with menu bar)
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

    @State private var lastValidNav: NavItem? = .containers

    var body: some View {
        @Bindable var vm = appVM

        NavigationSplitView {
            sidebar
        } content: {
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
                .navigationSplitViewColumnWidth(
                    min: isContentColumnCollapsed ? 0 : ColumnWidth.contentMin,
                    ideal: isContentColumnCollapsed ? 0 : ColumnWidth.contentIdeal,
                    max: isContentColumnCollapsed ? 0 : ColumnWidth.contentMax
                )
        } detail: {
            detailPanel
                .background(AppColors.sidebar)
        }
        .onChange(of: appVM.currentNav) { _, newNav in
            guard let newNav else { return }
            if newNav.isComingSoon {
                showComingSoonPanel()
                appVM.currentNav = lastValidNav
            } else {
                lastValidNav = newNav
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var vm = appVM

        return List(selection: $vm.currentNav) {
            Section("System") {
                ForEach(NavItem.Section.system.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
            Section("Docker") {
                ForEach(NavItem.Section.docker.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
            Section("Kubernetes") {
                ForEach(NavItem.Section.kubernetes.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
            Section("Linux") {
                ForEach(NavItem.Section.linux.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
            Section("Sandbox") {
                ForEach(NavItem.Section.sandbox.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarAccountButton()
        }
        .navigationSplitViewColumnWidth(ColumnWidth.sidebar)
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

/// Placeholder shown when no detail is available (e.g. Machines)
struct DetailPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textMuted)
            Text("No Selection")
                .foregroundStyle(AppColors.textSecondary)
                .font(.system(size: 15))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
        .environment(ContainersViewModel())
        .environment(ImagesViewModel())
        .environment(NetworksViewModel())
        .environment(VolumesViewModel())
}
