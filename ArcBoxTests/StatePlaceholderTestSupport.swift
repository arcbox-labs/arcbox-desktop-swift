import AppKit

@testable import ArcBox

@MainActor
func hostedStateView(in view: NSView) -> StatePlaceholderView? {
    guard !view.isHiddenOrHasHiddenAncestor else { return nil }
    if let placeholder = view as? StatePlaceholderView {
        return placeholder
    }
    return view.subviews.lazy.compactMap(hostedStateView).first
}

@MainActor
func hostedStateViewDisplays(_ text: String, in view: NSView) -> Bool {
    guard !view.isHiddenOrHasHiddenAncestor else { return false }

    if let placeholder = view as? StatePlaceholderView {
        switch placeholder.rootView.state {
        case .loading(let title):
            return title == text
        case .empty(_, let title, let message), .error(let title, let message):
            return title == text || message == text
        case .noSelection(_, let title), .plain(let title):
            return title == text
        }
    }

    if let emptyState = view as? CommandEmptyStateView {
        let content = emptyState.rootView
        return content.title == text
            || content.prompt == text
            || content.commands.contains {
                $0.command == text || $0.description == text
            }
    }

    return view.subviews.contains {
        hostedStateViewDisplays(text, in: $0)
    }
}

@MainActor
func hostedStateViewAction(
    titled title: String,
    in view: NSView
) -> (@MainActor () -> Void)? {
    guard !view.isHiddenOrHasHiddenAncestor else { return nil }

    if let placeholder = view as? StatePlaceholderView,
        let action = placeholder.rootView.action,
        action.title == title
    {
        return action.handler
    }

    return view.subviews.lazy.compactMap {
        hostedStateViewAction(titled: title, in: $0)
    }.first
}
