import Foundation
import Testing
@testable import VibeIslandAgentKit
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

@Suite("VibeIslandAgentConfiguration")
struct VibeIslandAgentConfigurationTests {
    @Test("Default socket and binary live under an Atoll namespace, not OpenIsland")
    func namespacedDefaults() {
        let config = VibeIslandAgentConfiguration()
        #expect(config.socketURL.path.contains("/VibeIsland/"))
        #expect(config.socketURL.lastPathComponent == "agent-bridge.sock")
        #expect(config.managedBinaryURL.path.contains("/VibeIsland/"))
        #expect(!config.socketURL.path.contains("/OpenIsland/"))
    }

    @Test("Hook source must be the routing key 'claude', not a custom label")
    func hookSourceIsRoutingKey() {
        // The hooks CLI maps --source to HookSource to choose the Claude vs
        // Codex decoder; an unknown value silently falls back to .codex and
        // breaks Claude tracking. Lock the functional value in.
        #expect(VibeIslandAgentConfiguration.hookSource == "claude")
    }

    @Test("Hook command overrides the bridge socket and routes to the Claude decoder")
    func hookCommandCarriesSocketOverride() {
        let socket = URL(fileURLWithPath: "/tmp/vibeisland-test/agent-bridge.sock")
        let config = VibeIslandAgentConfiguration(
            socketURL: socket,
            managedBinaryURL: URL(fileURLWithPath: "/tmp/vibeisland-test/VibeIslandAgentHooks")
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
        let config = VibeIslandAgentConfiguration(socketURL: socket)
        let command = config.hookCommand(binaryPath: "/bin/hooks")
        // The space-bearing path must be single-quoted so /bin/sh keeps it as one token.
        #expect(command.contains("'/Users/dev/Library/Application Support/Atoll/agent-bridge.sock'"))
    }
}

@Suite("ClaudeSessionFilter")
struct ClaudeSessionFilterTests {
    @Test("Includes the surfaced agents (Claude family, Codex, Gemini, Antigravity, OpenCode)")
    func includesSurfacedAgents() {
        #expect(ClaudeSessionFilter.includes(.claudeCode))
        #expect(ClaudeSessionFilter.includes(.qoder))
        #expect(ClaudeSessionFilter.includes(.qwenCode))
        #expect(ClaudeSessionFilter.includes(.factory))
        #expect(ClaudeSessionFilter.includes(.codebuddy))
        #expect(ClaudeSessionFilter.includes(.kimiCLI))
        #expect(ClaudeSessionFilter.includes(.codex))
        #expect(ClaudeSessionFilter.includes(.geminiCLI))
        #expect(ClaudeSessionFilter.includes(.antigravity))
        #expect(ClaudeSessionFilter.includes(.openCode))
    }

    @Test("Excludes agents not yet surfaced")
    func excludesOtherAgents() {
        #expect(!ClaudeSessionFilter.includes(.cursor))
    }

    @Test("Filters a mixed state down to surfaced sessions only")
    func filtersMixedState() {
        let state = SessionState(sessions: [
            makeSession(id: "a", tool: .claudeCode),
            makeSession(id: "b", tool: .codex),
            makeSession(id: "c", tool: .qoder),
            makeSession(id: "d", tool: .cursor),
            makeSession(id: "e", tool: .antigravity),
        ])

        let surfaced = ClaudeSessionFilter.claudeSessions(in: state)
        let ids = Set(surfaced.map(\.id))
        // codex (b) and antigravity (e) are surfaced; cursor (d) is not.
        #expect(ids == ["a", "b", "c", "e"])
    }
}

@Suite("AntigravityHookPayload")
struct AntigravityHookPayloadTests {
    @Test("Decodes a real agy PreToolUse payload and maps core fields")
    func decodesToolCallPayload() throws {
        let json = """
        {"artifactDirectoryPath":"/Users/x/.gemini/antigravity-cli/brain/abc",
         "conversationId":"abc-123",
         "stepIdx":3,
         "toolCall":{"args":{"CommandLine":"echo hi","Cwd":"/repo","toolSummary":"Run echo hi"},"name":"run_command"},
         "transcriptPath":"/Users/x/.gemini/antigravity-cli/brain/abc/.system_generated/logs/transcript_full.jsonl",
         "workspacePaths":["/repo"]}
        """
        let payload = try JSONDecoder().decode(AntigravityHookPayload.self, from: Data(json.utf8))

        #expect(payload.sessionID == "abc-123")
        #expect(payload.cwd == "/repo")
        #expect(payload.toolCall?.name == "run_command")
        // Event is absent from the JSON; it defaults until the CLI injects it.
        #expect(payload.hookEventName == .notification)
        #expect(payload.transcriptPath?.hasSuffix("transcript_full.jsonl") == true)
        #expect(payload.toolActivitySummary == "Run echo hi")
    }

    @Test("Event name round-trips through the bridge command codec")
    func eventRoundTripsThroughBridge() throws {
        var payload = try JSONDecoder().decode(
            AntigravityHookPayload.self,
            from: Data(#"{"conversationId":"s1","workspacePaths":["/r"]}"#.utf8)
        )
        payload.hookEventName = .stop

        let command = BridgeCommand.processAntigravityHook(payload)
        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(BridgeCommand.self, from: data)

        guard case let .processAntigravityHook(roundTripped) = decoded else {
            Issue.record("expected processAntigravityHook")
            return
        }
        #expect(roundTripped.hookEventName == .stop)
        #expect(roundTripped.sessionID == "s1")
    }

    @Test("Session title and summaries are branded Antigravity, not Gemini")
    func brandedStrings() throws {
        var payload = AntigravityHookPayload(conversationId: "s", workspacePaths: ["/Users/x/repo"])
        payload.hookEventName = .sessionStart
        #expect(payload.sessionTitle == "Antigravity · repo")
        #expect(payload.implicitSummary.contains("Antigravity"))
    }
}

@Suite("AntigravityHookInstallationManager")
struct AntigravityHookInstallationManagerTests {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Install writes a registered plugin with a per-event hook command")
    func installWritesRegisteredPlugin() throws {
        let configRoot = try makeTempDir()
        let plugins = configRoot.appendingPathComponent("plugins")
        let bundled = configRoot.appendingPathComponent("OpenIslandHooks")
        try Data("#!/bin/sh\n".utf8).write(to: bundled)
        let managed = configRoot.appendingPathComponent("managed/VibeIslandAgentHooks")

        let manager = AntigravityHookInstallationManager(
            pluginsDirectory: plugins,
            managedHooksBinaryURL: managed
        )

        let status = try manager.install(hooksBinaryURL: bundled)
        #expect(status.managedHooksPresent)

        let hooksText = String(decoding: try Data(contentsOf: status.hooksFileURL), as: UTF8.self)
        #expect(hooksText.contains("\"PreToolUse\""))
        #expect(hooksText.contains("--source antigravity --event Stop"))

        // Registered in import_manifest.json beside the plugins folder.
        let registry = try Data(contentsOf: status.importManifestURL)
        #expect(AntigravityHookInstaller.importManifestContains(plugin: "vibeisland", data: registry))
    }

    @Test("Install preserves other plugins; uninstall only drops ours")
    func registryPreservesOtherPlugins() throws {
        let configRoot = try makeTempDir()
        let plugins = configRoot.appendingPathComponent("plugins")
        let bundled = configRoot.appendingPathComponent("OpenIslandHooks")
        try Data("#!/bin/sh\n".utf8).write(to: bundled)
        let registryURL = configRoot.appendingPathComponent("import_manifest.json")
        try Data(#"{"imports":[{"name":"other","source":"antigravity","components":["hooks"]}]}"#.utf8)
            .write(to: registryURL)

        let manager = AntigravityHookInstallationManager(
            pluginsDirectory: plugins,
            managedHooksBinaryURL: configRoot.appendingPathComponent("managed/VibeIslandAgentHooks")
        )

        _ = try manager.install(hooksBinaryURL: bundled)
        var registry = try Data(contentsOf: registryURL)
        #expect(AntigravityHookInstaller.importManifestContains(plugin: "other", data: registry))
        #expect(AntigravityHookInstaller.importManifestContains(plugin: "vibeisland", data: registry))

        let status = try manager.uninstall()
        #expect(!status.managedHooksPresent)
        registry = try Data(contentsOf: registryURL)
        #expect(AntigravityHookInstaller.importManifestContains(plugin: "other", data: registry))
        #expect(!AntigravityHookInstaller.importManifestContains(plugin: "vibeisland", data: registry))
    }
}
