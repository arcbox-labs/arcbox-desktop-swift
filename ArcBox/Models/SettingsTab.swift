enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case account = "Account"
    case system = "System"
    case fleet = "Fleet"
    // TODO: Implement network settings (ABXD-88)
    // case network = "Network"
    case storage = "Storage"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .general: "gearshape"
        case .account: "person.circle"
        case .system: "square.grid.2x2"
        case .fleet: "server.rack"
        // case .network: "globe"
        case .storage: "externaldrive"
        }
    }
}
