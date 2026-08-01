import AppKit
import DockerClient
import SwiftUI
import UniformTypeIdentifiers

/// Platform options for pulling images
enum ImagePlatform: String, CaseIterable, Identifiable {
    case auto = "auto"
    case linuxAmd64 = "linux/amd64"
    case linuxArm64 = "linux/arm64"

    var id: String { rawValue }
}

/// Pull image dialog presented as a sheet
struct PullImageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ImagesViewModel.self) private var vm
    @Environment(\.dockerClient) private var docker

    @State private var isPulling = false
    /// Copied out of the view model rather than observed: the list behind this sheet has an
    /// `.errorToast` on the same `lastError`, and the toast clears it after four seconds even
    /// though it is hidden — which would wipe this message while the form is still open.
    @State private var errorMessage: String?
    @State private var image = ""
    @State private var platform: ImagePlatform = .auto

    private var imageIsEmpty: Bool {
        image.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            VStack(alignment: .leading, spacing: 4) {
                Text("Pull Image")
                    .font(.system(size: 13, weight: .semibold))
                Text("Images are used to run containers. They contain an application and its dependencies.")
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
                    TextField("Image", text: $image, prompt: Text("e.g. alpine:latest"))
                    Picker("Platform", selection: $platform) {
                        ForEach(ImagePlatform.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isPulling)

            // Footer buttons
            HStack {
                Button("Import...") {
                    guard !isPulling else { return }
                    let panel = NSOpenPanel()
                    var types: [UTType] = [.gzip]
                    if let tar = UTType(filenameExtension: "tar") { types.insert(tar, at: 0) }
                    panel.allowedContentTypes = types
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    isPulling = true
                    Task {
                        let ok = await vm.importImage(tarURL: url, docker: docker)
                        isPulling = false
                        if ok { dismiss() } else { errorMessage = vm.lastError }
                    }
                }
                .disabled(isPulling)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isPulling)

                Button("Pull") {
                    guard !isPulling else { return }
                    isPulling = true
                    Task {
                        let ok = await vm.pullImage(
                            image,
                            platform: platform == .auto ? nil : platform.rawValue,
                            docker: docker)
                        isPulling = false
                        if ok { dismiss() } else { errorMessage = vm.lastError }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isPulling || imageIsEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: AppMetrics.sheetWidth, height: 270)
        .interactiveDismissDisabled(isPulling)
    }
}
