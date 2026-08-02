import GRPCCore

/// Helpers for routing sandbox RPCs to a machine.
public enum SandboxMetadata {
    /// Build metadata containing the local `x-machine` routing header.
    ///
    /// The daemon uses the System VM when the header is absent; Desktop sends
    /// it explicitly so the selected machine remains unambiguous.
    public static func forMachine(_ machineID: String) -> Metadata {
        ["x-machine": .string(machineID)]
    }
}
