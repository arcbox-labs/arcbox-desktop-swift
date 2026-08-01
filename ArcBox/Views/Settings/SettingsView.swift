import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) private var appVM

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            settingsContent
                .navigationTitle(appVM.settingsTab?.rawValue ?? "")
                .background(AppColors.background)
        }
        .frame(minWidth: 700, minHeight: 580)
        .background(AppColors.background)
    }

    private var sidebar: some View {
        @Bindable var vm = appVM

        return ZStack {
            AppColors.sidebar
                .ignoresSafeArea(.container, edges: [.top, .bottom, .leading])

            List(SettingsTab.allCases, selection: $vm.settingsTab) { tab in
                Label(tab.rawValue, systemImage: tab.sfSymbol)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(AppColors.sidebar)
        .navigationSplitViewColumnWidth(180)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch appVM.settingsTab {
        case .general:
            GeneralSettingsView()
        case .account:
            AccountSettingsView()
        case .system:
            SystemSettingsView()
        // TODO: Implement network settings (ABXD-88)
        // case .network:
        //     NetworkSettingsView()
        case .storage:
            StorageSettingsView()
        case nil:
            EmptyView()
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppViewModel())
}
