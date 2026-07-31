import AppKit
import ArcBoxClient
import SwiftUI
import os

/// Files tab backed by an already-mounted local rootfs directory.
struct ContainerFilesTab: View {
    let container: ContainerViewModel

    @Environment(\.arcboxClient) private var arcboxClient

    @State private var selectedPath: String?
    @State private var rootURL: URL?
    @State private var layers: LayeredRootFS?
    /// Stack layers missing from what was browsed, by index — a set so
    /// exclusions seen in different directories union instead of collapsing
    /// to the worst one.
    @State private var excludedLayerIndices: Set<Int> = []
    /// Layers whose guest path maps to no exported root: never in the stack,
    /// so they have no index, but still missing from what the user sees.
    @State private var unmappableLayerCount = 0
    @State private var totalLayerCount = 0
    @State private var errorMessage: String?
    @State private var isLoadingRoot = false
    @State private var refreshToken = UUID()
    @State private var showHiddenFiles = LocalRootFSService.finderDefaultShowHiddenFiles()

    private var outlineReloadID: String {
        // Client availability is part of the key: the environment client is
        // nil during app startup, and the daemon-side resolution must re-run
        // once it is injected — `.task(id:)` only restarts on an id change.
        "\(container.id)|\(container.resolvedRootFSMountPath ?? "")|\(arcboxClient != nil)|\(showHiddenFiles)|\(refreshToken.uuidString)"
    }

    private var selectedURL: URL? {
        guard let selectedPath else { return nil }
        return URL(fileURLWithPath: selectedPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task(id: outlineReloadID) {
            await resolveRootPath()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)

            Text(rootURL?.path ?? container.resolvedRootFSMountPath ?? "No rootfs mount path")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let layers, layers.isComposed {
                LayerMergeBadge(
                    total: max(totalLayerCount, layers.layers.count),
                    unavailable: excludedLayerIndices.count + unmappableLayerCount
                )
            }

            Spacer()

            Button(
                action: { showHiddenFiles.toggle() },
                label: {
                    Image(systemName: showHiddenFiles ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                }
            )
            .buttonStyle(.plain)
            .help(showHiddenFiles ? "Hide hidden files" : "Show hidden files")

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Button(action: revealSelectedInFinder) {
                Image(systemName: "finder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(selectedURL == nil)
            .help("Reveal selected in Finder")
        }
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isLoadingRoot {
            VStack {
                Spacer()
                ProgressView("Loading files...")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
        } else if let errorMessage {
            errorState(errorMessage)
        } else if let rootURL {
            LocalRootFSOutlineView(
                rootURL: rootURL,
                layers: layers,
                showHiddenFiles: showHiddenFiles,
                reloadID: outlineReloadID,
                selectedPath: $selectedPath,
                onOpenURL: { url in
                    _ = NSWorkspace.shared.open(url)
                },
                onExcludedLayers: { indices in
                    // Union, never replace: a layer dropped once has already
                    // left holes in what the user browsed, and two
                    // directories can fail on two different layers.
                    excludedLayerIndices.formUnion(indices)
                }
            )
        } else {
            errorState("Container has no configured rootfs mount path.")
        }
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.textMuted)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Text(
                "Container filesystems are browsed through the read-only ~/ArcBox export, "
                    + "merging the container's writable layer over the image layers below it."
            )
            .font(.system(size: 12))
            .foregroundStyle(AppColors.textMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)

            Button("Refresh") {
                refresh()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() {
        refreshToken = UUID()
    }

    private func resolveRootPath() async {
        errorMessage = nil
        isLoadingRoot = true
        selectedPath = nil
        layers = nil
        excludedLayerIndices = []
        unmappableLayerCount = 0
        totalLayerCount = 0

        // Inspect-provided path (classic graph drivers) is already a merged
        // rootfs; under the containerd image store inspect carries no paths,
        // so the daemon resolves the layer stack and the tab merges it.
        var guestPaths: [String] = []
        if let mountPath = container.resolvedRootFSMountPath {
            guestPaths = [mountPath]
        } else {
            guestPaths = await resolveViaDaemon()
        }

        // The resolved paths are guest paths; browse them through ~/ArcBox.
        // A layer whose path falls outside the exported roots cannot be
        // browsed at all, so it counts against the view's completeness rather
        // than quietly shrinking the stack.
        let hostURLs = guestPaths.compactMap(GuestDataMount.hostURL(forGuestPath:))
        totalLayerCount = guestPaths.count
        let unmappableCount = guestPaths.count - hostURLs.count
        guard let rootHostURL = hostURLs.first else {
            rootURL = nil
            errorMessage =
                guestPaths.isEmpty
                ? "Container has no resolvable filesystem path."
                : "Container filesystem path is outside the guest data root."
            isLoadingRoot = false
            return
        }

        do {
            rootURL = try LocalRootFSService.resolveRootURL(path: rootHostURL.path)
            layers = hostURLs.count > 1 ? LayeredRootFS(layers: hostURLs) : nil
            // A layer the export cannot currently serve merges as empty, so
            // the view would be quietly incomplete; count them and say so
            // rather than passing a partial filesystem off as the whole one.
            // Listings report further failures as they happen (a layer can
            // die after this check), and the badge keeps the worst seen.
            unmappableLayerCount = unmappableCount
            excludedLayerIndices = Set(
                hostURLs.enumerated()
                    .filter { (try? LocalRootFSService.resolveRootURL(path: $0.element.path)) == nil }
                    .map(\.offset))
        } catch {
            rootURL = nil
            errorMessage = GuestDataMount.unavailableMessage(subject: "This container's filesystem")
        }

        isLoadingRoot = false
    }

    /// Resolves the container's snapshot layer stack via the daemon.
    ///
    /// Under the containerd image store the layer directories live in
    /// containerd's snapshotter, so the daemon queries the guest and returns
    /// guest paths: the writable (upper) layer the container wrote, followed
    /// by the image layers below it — overlay precedence order.
    private func resolveViaDaemon() async -> [String] {
        guard let arcboxClient else { return [] }
        var request = Arcbox_V1_ResolveContainerFsRequest()
        request.containerID = container.id
        do {
            let response = try await arcboxClient.system.resolveContainerFs(
                request, options: ArcBoxClient.defaultCallOptions)
            var paths: [String] = []
            if !response.upperDir.isEmpty {
                paths.append(response.upperDir)
            }
            paths.append(contentsOf: response.lowerDirs.filter { !$0.isEmpty })
            return paths
        } catch {
            Log.daemon.error(
                "Failed to resolve container fs: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    private func revealSelectedInFinder() {
        guard let url = selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
