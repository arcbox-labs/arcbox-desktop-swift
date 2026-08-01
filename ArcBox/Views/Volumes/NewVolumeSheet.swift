import AppKit
import DockerClient
import SwiftUI
import UniformTypeIdentifiers

/// New volume dialog presented as a sheet
struct NewVolumeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VolumesViewModel.self) private var vm
    @Environment(\.dockerClient) private var docker

    @State private var isCreating = false
    /// Copied out of the view model rather than observed: the list behind this sheet has an
    /// `.errorToast` on the same `lastError`, and the toast clears it after four seconds even
    /// though it is hidden — which would wipe this message while the form is still open.
    @State private var errorMessage: String?
    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            VStack(alignment: .leading, spacing: 4) {
                Text("New Volume")
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    "Volumes are for sharing data between containers. Unlike bind mounts, they are stored "
                        + "on a native Linux file system, making them faster and more reliable."
                )
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                SheetErrorMessage(message: errorMessage)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }

            // Form
            Form {
                Section {
                    TextField("Name", text: $name)
                }
            }
            .formStyle(.grouped)
            .disabled(isCreating)

            // Footer buttons
            HStack {
                Button("Import...") {
                    guard !isCreating else { return }
                    let panel = NSOpenPanel()
                    var types: [UTType] = [.gzip]
                    if let tar = UTType(filenameExtension: "tar") { types.insert(tar, at: 0) }
                    panel.allowedContentTypes = types
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    isCreating = true
                    Task {
                        let ok = await vm.importVolume(name: name, tarURL: url, docker: docker)
                        isCreating = false
                        if ok { dismiss() } else { errorMessage = vm.lastError }
                    }
                }
                .disabled(isCreating)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)

                Button("Create") {
                    guard !isCreating else { return }
                    isCreating = true
                    Task {
                        let ok = await vm.createVolume(name: name, docker: docker)
                        isCreating = false
                        if ok { dismiss() } else { errorMessage = vm.lastError }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: AppMetrics.sheetWidth, height: 240)
        .interactiveDismissDisabled(isCreating)
    }
}
