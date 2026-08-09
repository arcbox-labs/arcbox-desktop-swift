import AppKit
import SwiftUI

@MainActor
final class CommandEmptyStateView: NSHostingView<CommandEmptyStateContent> {
    struct Command {
        let command: String
        let description: String
    }

    init(
        systemImage: String,
        title: String,
        prompt: String,
        commands: [Command]
    ) {
        super.init(
            rootView: CommandEmptyStateContent(
                systemImage: systemImage,
                title: title,
                prompt: prompt,
                commands: commands
            )
        )
        sizingOptions = []
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
        setAccessibilityHelp(prompt)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: CommandEmptyStateContent) {
        fatalError("init(rootView:) has not been implemented")
    }
}

struct CommandEmptyStateContent: View {
    let systemImage: String
    let title: String
    let prompt: String
    let commands: [CommandEmptyStateView.Command]

    var body: some View {
        EmptyStateView(icon: systemImage, title: title) {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                ForEach(commands.indices, id: \.self) { index in
                    CommandHint(
                        command: commands[index].command,
                        description: commands[index].description
                    )
                }
            }
        }
    }
}
