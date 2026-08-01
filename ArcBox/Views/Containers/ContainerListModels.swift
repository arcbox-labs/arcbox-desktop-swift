import AppKit

@MainActor
final class ContainersOutlineView: NSOutlineView {
    override func frameOfOutlineCell(atRow _: Int) -> NSRect {
        .zero
    }
}

struct ContainerListPresentation: Equatable {
    let container: ContainerViewModel

    static func == (
        lhs: ContainerListPresentation,
        rhs: ContainerListPresentation
    ) -> Bool {
        lhs.container.id == rhs.container.id
            && lhs.container.name == rhs.container.name
            && lhs.container.image == rhs.container.image
            && lhs.container.state == rhs.container.state
            && lhs.container.isTransitioning == rhs.container.isTransitioning
            && lhs.container.ports == rhs.container.ports
            && lhs.container.composeProject == rhs.container.composeProject
            && lhs.container.composeService == rhs.container.composeService
            && lhs.container.iconURL == rhs.container.iconURL
    }
}

enum ContainerListNodePresentation: Equatable {
    case section(String)
    case compose(project: String, containers: [ContainerListPresentation])
    case container(ContainerListPresentation)
}

enum ContainerListNodeID: Hashable {
    case section(String)
    case compose(String)
    case container(String)
}

final class ContainerListNode: NSObject {
    let presentation: ContainerListNodePresentation
    let children: [ContainerListNode]

    var id: ContainerListNodeID {
        switch presentation {
        case .section(let title):
            .section(title)
        case .compose(let project, _):
            .compose(project)
        case .container(let container):
            .container(container.container.id)
        }
    }

    init(_ presentation: ContainerListNodePresentation) {
        self.presentation = presentation
        switch presentation {
        case .compose(_, let containers):
            children = containers.map {
                ContainerListNode(.container($0))
            }
        case .section, .container:
            children = []
        }
    }
}
