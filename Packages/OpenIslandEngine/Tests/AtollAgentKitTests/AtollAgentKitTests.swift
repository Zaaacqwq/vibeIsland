import Foundation
import Testing
@testable import AtollAgentKit
import OpenIslandCore

private func makeSession(
    id: String,
    tool: AgentTool,
    phase: SessionPhase = .running
) -> AgentSession {
    AgentSession(
        id: id,
        title: "Session \(id)",
        tool: tool,
        phase: phase,
        summary: "",
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )
}

@Suite("AtollAgentConfiguration")
struct AtollAgentConfigurationTests {
    @Test("Default socket and binary live under an Atoll namespace, not OpenIsland")
    func namespacedDefaults() {
        let config = AtollAgentConfiguration()
        #expect(config.socketURL.path.contains("/Atoll/"))
        #expect(config.socketURL.lastPathComponent == "agent-bridge.sock")
        #expect(config.managedBinaryURL.path.contains("/Atoll/"))
        #expect(!config.socketURL.path.contains("/OpenIsland/"))
    }

    @Test("Hook source must be the routing key 'claude', not a custom label")
    func hookSourceIsRoutingKey() {
        // The hooks CLI maps --source to HookSource to choose the Claude vs
        // Codex decoder; an unknown value silently falls back to .codex and
        // breaks Claude tracking. Lock the functional value in.
        #expect(AtollAgentConfiguration.hookSource == "claude")
    }

    @Test("Hook command overrides the bridge socket and routes to the Claude decoder")
    func hookCommandCarriesSocketOverride() {
        let socket = URL(fileURLWithPath: "/tmp/atoll-test/agent-bridge.sock")
        let config = AtollAgentConfiguration(
            socketURL: socket,
            managedBinaryURL: URL(fileURLWithPath: "/tmp/atoll-test/AtollAgentHooks")
        )
        let command = config.hookCommand(binaryPath: "/Applications/Atoll.app/Contents/Helpers/OpenIslandHooks")

        #expect(command.hasPrefix("OPEN_ISLAND_SOCKET_PATH="))
        #expect(command.contains(socket.path))
        #expect(command.contains("--source claude"))
        #expect(command.contains("OpenIslandHooks"))
    }

    @Test("Socket paths containing spaces stay shell-safe")
    func hookCommandQuotesSocketPath() {
        let socket = URL(fileURLWithPath: "/Users/dev/Library/Application Support/Atoll/agent-bridge.sock")
        let config = AtollAgentConfiguration(socketURL: socket)
        let command = config.hookCommand(binaryPath: "/bin/hooks")
        // The space-bearing path must be single-quoted so /bin/sh keeps it as one token.
        #expect(command.contains("'/Users/dev/Library/Application Support/Atoll/agent-bridge.sock'"))
    }
}

@Suite("ClaudeSessionFilter")
struct ClaudeSessionFilterTests {
    @Test("Includes Claude Code and its hook-compatible forks")
    func includesClaudeFamily() {
        #expect(ClaudeSessionFilter.includes(.claudeCode))
        #expect(ClaudeSessionFilter.includes(.qoder))
        #expect(ClaudeSessionFilter.includes(.qwenCode))
        #expect(ClaudeSessionFilter.includes(.factory))
        #expect(ClaudeSessionFilter.includes(.codebuddy))
        #expect(ClaudeSessionFilter.includes(.kimiCLI))
    }

    @Test("Excludes non-Claude agents for the MVP")
    func excludesOtherAgents() {
        #expect(!ClaudeSessionFilter.includes(.codex))
        #expect(!ClaudeSessionFilter.includes(.geminiCLI))
        #expect(!ClaudeSessionFilter.includes(.openCode))
        #expect(!ClaudeSessionFilter.includes(.cursor))
    }

    @Test("Filters a mixed state down to Claude-family sessions only")
    func filtersMixedState() {
        let state = SessionState(sessions: [
            makeSession(id: "a", tool: .claudeCode),
            makeSession(id: "b", tool: .codex),
            makeSession(id: "c", tool: .qoder),
            makeSession(id: "d", tool: .cursor),
        ])

        let claude = ClaudeSessionFilter.claudeSessions(in: state)
        let ids = Set(claude.map(\.id))
        #expect(ids == ["a", "c"])
    }
}
