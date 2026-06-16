import Foundation
import OpenIslandCore

/// Atoll-specific namespacing for the vendored Open Island agent engine.
///
/// The engine defaults (`~/Library/Application Support/OpenIsland/bridge.sock`,
/// a managed `OpenIslandHooks` binary) are shared with a standalone Open Island
/// install. To let Atoll host agent monitoring without colliding with a
/// co-installed Open Island, every externally-visible identity — the bridge
/// socket, the managed hooks binary, and the installed hook command — is
/// rebased under an `Atoll` namespace.
public struct AtollAgentConfiguration: Sendable {
    /// `--source` value passed to the hooks CLI. This is a **routing key** the
    /// CLI maps to `HookSource` (it picks the Claude vs Codex decoder from it),
    /// so it must be the functional value `claude` — not a custom label.
    /// Atoll's namespacing/collision-avoidance lives in the socket path and the
    /// managed binary location instead.
    public static let hookSource = "claude"

    /// Environment variable the engine's `BridgeSocketLocation.currentURL`
    /// reads to override the default socket path. Re-exported here so the
    /// installed hook command and the bridge server stay in lockstep.
    public static let socketEnvironmentKey = "OPEN_ISLAND_SOCKET_PATH"

    public let socketURL: URL
    public let managedBinaryURL: URL

    public init(
        socketURL: URL = AtollAgentConfiguration.defaultSocketURL,
        managedBinaryURL: URL = AtollAgentConfiguration.defaultManagedBinaryURL
    ) {
        self.socketURL = socketURL
        self.managedBinaryURL = managedBinaryURL
    }

    /// `~/Library/Application Support/Atoll/agent-bridge.sock`
    public static var defaultSocketURL: URL {
        atollSupportDirectory().appendingPathComponent("agent-bridge.sock")
    }

    /// `~/Library/Application Support/Atoll/AtollAgentHooks`
    public static var defaultManagedBinaryURL: URL {
        atollSupportDirectory().appendingPathComponent("AtollAgentHooks")
    }

    private static func atollSupportDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Atoll")
    }

    /// Hook command written into `~/.claude/settings.json`. Prefixes the bridge
    /// socket override so the hooks binary connects to Atoll's socket rather
    /// than the shared engine default. Executed by Claude Code through `/bin/sh`,
    /// so the `VAR=value command` prefix is valid.
    public func hookCommand(binaryPath: String) -> String {
        let base = ClaudeHookInstaller.hookCommand(for: binaryPath, source: Self.hookSource)
        return "\(Self.socketEnvironmentKey)=\(shellQuote(socketURL.path)) \(base)"
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
