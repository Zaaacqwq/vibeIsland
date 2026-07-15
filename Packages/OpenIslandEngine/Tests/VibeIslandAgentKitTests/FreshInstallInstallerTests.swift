import Foundation
import Testing
import OpenIslandCore

// MARK: - Fresh-install verification for every agent integration.
//
// Goal: prove that on a machine that has NEVER installed VibeIsland, clicking
// "Install" for each coding agent produces a correct, working hook/plugin
// configuration — and that re-installing (or upgrading over an older/legacy
// install) never leaves duplicate or stale entries.
//
// These mirror the manual end-to-end checks (see docs/AGENT_HOOK_TESTING.md):
// they exercise the pure installer transforms directly, so they run in CI with
// no app, no GUI, and no authenticated CLIs.
//
// The current install binary path a fresh machine would receive.
private let freshBinary =
    "/Users/tester/Library/Application Support/VibeIsland/VibeIslandAgentHooks"
// A stale command a machine that installed an OLD build would carry. The
// installers must scrub this during (re)install — a leftover blocking copy is
// what hangs Codex approvals ("Running 2 PermissionRequest hooks").
private let legacyCommand =
    "'/Users/tester/Library/Application Support/OpenIsland/bin/OpenIslandHooks'"
private let legacyPathFragment = "OpenIsland/bin/OpenIslandHooks"

// MARK: - JSON helpers

private func decode(_ data: Data?) throws -> [String: Any] {
    let data = try #require(data, "installer produced no file contents")
    return try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any],
        "installer output is not a JSON object"
    )
}

/// Commands under the Claude/Codex/Gemini nested schema:
/// `hooks -> <Event> -> [ { hooks: [ { command } ] } ]`.
private func nestedCommands(_ root: [String: Any], event: String) -> [String] {
    let hooks = root["hooks"] as? [String: Any] ?? [:]
    let groups = hooks[event] as? [[String: Any]] ?? []
    return groups.flatMap { group in
        (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
    }
}

/// Commands under Cursor's flat schema: `hooks -> <Event> -> [ { command } ]`.
private func flatCommands(_ root: [String: Any], event: String) -> [String] {
    let hooks = root["hooks"] as? [String: Any] ?? [:]
    let entries = hooks[event] as? [[String: Any]] ?? []
    return entries.compactMap { $0["command"] as? String }
}

private func text(_ data: Data?) -> String {
    guard let data else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
}

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibeisland-freshinstall-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Claude Code

@Test("Claude fresh install registers a managed hook for every event")
func claudeFreshInstall() throws {
    let command = ClaudeHookInstaller.hookCommand(for: freshBinary)
    #expect(command.contains(freshBinary))
    #expect(command.contains("--source claude"))
    #expect(!command.contains(legacyPathFragment))

    let mutation = try ClaudeHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command)
    #expect(mutation.changed)
    #expect(mutation.managedHooksPresent)

    let root = try decode(mutation.contents)
    // Every documented event must carry exactly the managed command once.
    for event in ["UserPromptSubmit", "SessionStart", "Stop", "PermissionRequest",
                  "PreToolUse", "PostToolUse", "Notification"] {
        #expect(nestedCommands(root, event: event) == [command], "event \(event)")
    }
}

@Test("Claude re-install is idempotent (no duplicate hooks)")
func claudeReinstallIdempotent() throws {
    let command = ClaudeHookInstaller.hookCommand(for: freshBinary)
    let first = try ClaudeHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command)
    let second = try ClaudeHookInstaller.installSettingsJSON(existingData: first.contents, hookCommand: command)

    #expect(!second.changed, "second identical install should be a no-op")
    let root = try decode(second.contents)
    #expect(nestedCommands(root, event: "PermissionRequest") == [command])
}

@Test("Claude install preserves the user's own unrelated hooks")
func claudePreservesUserHooks() throws {
    let userHook = "/usr/bin/my-linter"
    let existing = try JSONSerialization.data(withJSONObject: [
        "hooks": ["PostToolUse": [["hooks": [["type": "command", "command": userHook]]]]]
    ])
    let command = ClaudeHookInstaller.hookCommand(for: freshBinary)
    let mutation = try ClaudeHookInstaller.installSettingsJSON(existingData: existing, hookCommand: command)
    let root = try decode(mutation.contents)
    #expect(nestedCommands(root, event: "PostToolUse").contains(userHook))
    #expect(nestedCommands(root, event: "PostToolUse").contains(command))
}

@Test("Claude uninstall removes managed hooks")
func claudeUninstall() throws {
    let command = ClaudeHookInstaller.hookCommand(for: freshBinary)
    let installed = try ClaudeHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command)
    let removed = try ClaudeHookInstaller.uninstallSettingsJSON(
        existingData: installed.contents, managedCommand: command
    )
    #expect(removed.changed)
    // File is emptied of our hooks: the managed binary must no longer appear.
    #expect(!text(removed.contents).contains(freshBinary))
}

// MARK: - Codex

@Test("Codex fresh install registers a managed hook for every event")
func codexFreshInstall() throws {
    let command = CodexHookInstaller.hookCommand(for: freshBinary)
    #expect(command.contains(freshBinary))

    let mutation = try CodexHookInstaller.installHooksJSON(existingData: nil, hookCommand: command)
    #expect(mutation.changed)
    #expect(mutation.hasRemainingHooks)

    let root = try decode(mutation.contents)
    for event in ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop"] {
        #expect(nestedCommands(root, event: event) == [command], "event \(event)")
    }
}

@Test("Codex re-install is idempotent (no duplicate hooks)")
func codexReinstallIdempotent() throws {
    let command = CodexHookInstaller.hookCommand(for: freshBinary)
    let first = try CodexHookInstaller.installHooksJSON(existingData: nil, hookCommand: command)
    let second = try CodexHookInstaller.installHooksJSON(existingData: first.contents, hookCommand: command)
    #expect(!second.changed)
    let root = try decode(second.contents)
    #expect(nestedCommands(root, event: "PermissionRequest") == [command])
}

// This is the regression guard for the real bug found in manual testing: a
// machine carrying a legacy OpenIslandHooks PermissionRequest hook alongside the
// new one made Codex hang after approval (two blocking hooks, one answer). A
// (re)install MUST scrub the legacy copy so exactly one blocking hook remains.
@Test("Codex install scrubs a stale legacy hook (no post-approval hang)")
func codexScrubsLegacyDuplicate() throws {
    let existing = try JSONSerialization.data(withJSONObject: [
        "hooks": [
            "PermissionRequest": [["hooks": [["type": "command", "command": legacyCommand]]]],
            "Stop": [["hooks": [["type": "command", "command": legacyCommand]]]],
        ]
    ])
    let command = CodexHookInstaller.hookCommand(for: freshBinary)
    let mutation = try CodexHookInstaller.installHooksJSON(existingData: existing, hookCommand: command)
    let root = try decode(mutation.contents)

    // Exactly one blocking PermissionRequest hook — the new one — must remain.
    #expect(nestedCommands(root, event: "PermissionRequest") == [command])
    #expect(!text(mutation.contents).contains(legacyPathFragment), "legacy hook must be removed")
}

@Test("Codex uninstall removes managed hooks")
func codexUninstall() throws {
    let command = CodexHookInstaller.hookCommand(for: freshBinary)
    let installed = try CodexHookInstaller.installHooksJSON(existingData: nil, hookCommand: command)
    let removed = try CodexHookInstaller.uninstallHooksJSON(
        existingData: installed.contents, managedCommand: command
    )
    #expect(removed.changed)
    #expect(!removed.hasRemainingHooks)
}

// MARK: - Codex hook trust (config.toml `[hooks.state."…"]` entries)
//
// Codex 0.130+ discovers user-level hooks but refuses to RUN them until each
// carries a matching `trusted_hash` in config.toml. Install must therefore
// persist trust entries or the integration silently does nothing.

private let codexHooksPath = "/Users/tester/.codex/hooks.json"

// Golden vectors captured from a real codex-cli 0.144.1 install: the hashes
// below are the exact `trusted_hash` values Codex itself persisted for these
// hooks. They pin our Swift implementation to codex-rs `command_hook_hash`.
@Test("Codex trust hashes match values persisted by codex-cli itself")
func codexTrustHashGoldenVectors() throws {
    let command = "'/Users/zaaac/Library/Application Support/OpenIsland/bin/OpenIslandHooks'"
    let hooksJSON = try JSONSerialization.data(withJSONObject: [
        "hooks": [
            "SessionStart": [[
                "matcher": "startup|resume",
                "hooks": [["type": "command", "command": command, "timeout": 45]],
            ]],
            "UserPromptSubmit": [["hooks": [["type": "command", "command": command, "timeout": 45]]]],
            "PermissionRequest": [["hooks": [["type": "command", "command": command, "timeout": 3600]]]],
            "Stop": [["hooks": [["type": "command", "command": command, "timeout": 45]]]],
        ]
    ])

    let path = "/Users/zaaac/.codex/hooks.json"
    let entries = CodexHookTrust.managedEntries(
        hooksData: hooksJSON, hooksFilePath: path, managedCommand: command
    )
    let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.trustedHash) })

    #expect(byKey["\(path):session_start:0:0"]
        == "sha256:557d1cfc0634e7d2a80c06a5054af6954a810c885077bdbd0a20769c2c582dab")
    #expect(byKey["\(path):user_prompt_submit:0:0"]
        == "sha256:f780fcb21d29f75309911ce76d8bb213edb0a9fe6e73f6c153faaf6d3240dbce")
    #expect(byKey["\(path):permission_request:0:0"]
        == "sha256:af957e298db8180e76e07ace034b8560176e366273c4bf1191d1c36780402352")
    #expect(byKey["\(path):stop:0:0"]
        == "sha256:049bb38070a8ebc8101c9288bf9b14e1c149fe9651c152a8e561bcf664be4c63")
}

@Test("Codex fresh install produces trust entries for every managed hook")
func codexFreshInstallTrustEntries() throws {
    let command = CodexHookInstaller.hookCommand(for: freshBinary)
    let mutation = try CodexHookInstaller.installHooksJSON(existingData: nil, hookCommand: command)

    let entries = CodexHookTrust.managedEntries(
        hooksData: mutation.contents, hooksFilePath: codexHooksPath, managedCommand: command
    )
    let labels = entries.map(\.key).sorted()
    #expect(labels == [
        "\(codexHooksPath):permission_request:0:0",
        "\(codexHooksPath):session_start:0:0",
        "\(codexHooksPath):stop:0:0",
        "\(codexHooksPath):user_prompt_submit:0:0",
    ].sorted())

    // Writing them into an existing config marks the hooks trusted; a second
    // apply is a no-op (idempotent re-install).
    let config = CodexHookTrust.applying(entries: entries, removingKeys: [], to: "[features]\nhooks = true\n")
    #expect(config.changed)
    #expect(config.contents.contains("[hooks.state.\"\(codexHooksPath):stop:0:0\"]"))
    #expect(CodexHookTrust.managedHooksTrusted(
        configContents: config.contents, hooksData: mutation.contents,
        hooksFilePath: codexHooksPath, managedCommand: command
    ))

    let again = CodexHookTrust.applying(entries: entries, removingKeys: [], to: config.contents)
    #expect(!again.changed)
}

@Test("Codex trust removal drops only our entries and preserves others")
func codexTrustRemovalPreservesOthers() throws {
    let command = CodexHookInstaller.hookCommand(for: freshBinary)
    let mutation = try CodexHookInstaller.installHooksJSON(existingData: nil, hookCommand: command)
    let entries = CodexHookTrust.managedEntries(
        hooksData: mutation.contents, hooksFilePath: codexHooksPath, managedCommand: command
    )

    let foreign = "[hooks.state.\"\(codexHooksPath):pre_tool_use:3:0\"]\ntrusted_hash = \"sha256:abc\"\n"
    let installed = CodexHookTrust.applying(entries: entries, removingKeys: [], to: foreign)
    let removed = CodexHookTrust.applying(
        entries: [], removingKeys: entries.map(\.key), to: installed.contents
    )

    #expect(removed.changed)
    #expect(!removed.contents.contains(":stop:0:0"))
    #expect(removed.contents.contains(":pre_tool_use:3:0"), "unrelated trust entries must survive")
    #expect(!CodexHookTrust.managedHooksTrusted(
        configContents: removed.contents, hooksData: mutation.contents,
        hooksFilePath: codexHooksPath, managedCommand: command
    ))
}

@Test("Codex end-to-end install/uninstall keeps config.toml trust in sync")
func codexManagerTrustLifecycle() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let bundled = dir.appendingPathComponent("OpenIslandHooks")
    try Data("#!/bin/sh\n".utf8).write(to: bundled)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)

    let manager = CodexHookInstallationManager(
        codexDirectory: dir.appendingPathComponent(".codex"),
        managedHooksBinaryURL: dir.appendingPathComponent("managed/VibeIslandAgentHooks"),
        featureKeyProvider: { .current }
    )

    let installed = try manager.install(hooksBinaryURL: bundled)
    #expect(installed.managedHooksPresent)
    #expect(installed.managedHooksTrusted)
    #expect(installed.managedHooksActive)

    let config = try String(contentsOf: installed.configURL, encoding: .utf8)
    #expect(config.contains("hooks = true"))
    #expect(config.contains("[hooks.state.\""))
    #expect(config.contains("trusted_hash = \"sha256:"))

    let removed = try manager.uninstall()
    #expect(!removed.managedHooksPresent)
    #expect(!removed.managedHooksTrusted)
    let cleaned = try String(contentsOf: removed.configURL, encoding: .utf8)
    #expect(!cleaned.contains("[hooks.state.\""), "uninstall must drop our trust entries")
}

// MARK: - Cursor

@Test("Cursor fresh install registers a managed hook for every event")
func cursorFreshInstall() throws {
    let command = CursorHookInstaller.hookCommand(for: freshBinary)
    #expect(command.contains("--source cursor"))

    let mutation = try CursorHookInstaller.installHooksJSON(existingData: nil, hookCommand: command)
    #expect(mutation.changed)
    #expect(mutation.managedHooksPresent)

    let root = try decode(mutation.contents)
    #expect(root["version"] as? Int == 1)
    for event in ["beforeShellExecution", "afterFileEdit", "stop"] {
        #expect(flatCommands(root, event: event) == [command], "event \(event)")
    }
}

@Test("Cursor re-install is idempotent (no duplicate hooks)")
func cursorReinstallIdempotent() throws {
    let command = CursorHookInstaller.hookCommand(for: freshBinary)
    let first = try CursorHookInstaller.installHooksJSON(existingData: nil, hookCommand: command)
    let second = try CursorHookInstaller.installHooksJSON(existingData: first.contents, hookCommand: command)
    #expect(!second.changed)
    let root = try decode(second.contents)
    #expect(flatCommands(root, event: "beforeShellExecution") == [command])
}

@Test("Cursor uninstall removes managed hooks")
func cursorUninstall() throws {
    let command = CursorHookInstaller.hookCommand(for: freshBinary)
    let installed = try CursorHookInstaller.installHooksJSON(existingData: nil, hookCommand: command)
    let removed = try CursorHookInstaller.uninstallHooksJSON(
        existingData: installed.contents, managedCommand: command
    )
    #expect(removed.changed)
    #expect(!text(removed.contents).contains(freshBinary))
}

// MARK: - Gemini

@Test("Gemini fresh install registers a managed hook for every event")
func geminiFreshInstall() throws {
    let command = GeminiHookInstaller.hookCommand(for: freshBinary)
    #expect(command.contains("--source gemini"))

    let mutation = try GeminiHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command)
    #expect(mutation.changed)
    #expect(mutation.managedHooksPresent)

    let root = try decode(mutation.contents)
    for event in ["SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "Notification"] {
        #expect(nestedCommands(root, event: event) == [command], "event \(event)")
    }
}

@Test("Gemini re-install is idempotent (no duplicate hooks)")
func geminiReinstallIdempotent() throws {
    let command = GeminiHookInstaller.hookCommand(for: freshBinary)
    let first = try GeminiHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command)
    let second = try GeminiHookInstaller.installSettingsJSON(existingData: first.contents, hookCommand: command)
    #expect(!second.changed)
    let root = try decode(second.contents)
    #expect(nestedCommands(root, event: "SessionStart") == [command])
}

@Test("Gemini uninstall removes managed hooks")
func geminiUninstall() throws {
    let command = GeminiHookInstaller.hookCommand(for: freshBinary)
    let installed = try GeminiHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command)
    let removed = try GeminiHookInstaller.uninstallSettingsJSON(
        existingData: installed.contents, managedCommand: command
    )
    #expect(removed.changed)
    #expect(!text(removed.contents).contains(freshBinary))
}

// MARK: - Antigravity (agy) — plugin + registry

@Test("Antigravity fresh install builds a hooks file for every event")
func antigravityHooksFile() throws {
    let data = try AntigravityHookInstaller.hooksFileData(binaryPath: freshBinary)
    #expect(AntigravityHookInstaller.hooksFileContainsManagedCommand(data: data))

    let root = try decode(data)
    for event in AntigravityHookInstaller.events {
        let expected = AntigravityHookInstaller.hookCommand(for: freshBinary, event: event)
        #expect(nestedCommands(root, event: event.rawValue) == [expected], "event \(event.rawValue)")
        #expect(expected.contains("--event \(event.rawValue)"))
    }
}

@Test("Antigravity registers its plugin in import_manifest.json, idempotently")
func antigravityManifestRegistration() throws {
    let name = AntigravityHookInstaller.pluginDirectoryName
    let once = try AntigravityHookInstaller.importManifestData(addingPlugin: name, existing: nil)
    #expect(AntigravityHookInstaller.importManifestContains(plugin: name, data: once))

    // Registering again must not create a duplicate entry (agy loads plugins once).
    let twice = try AntigravityHookInstaller.importManifestData(addingPlugin: name, existing: once)
    let root = try decode(twice)
    let imports = try #require(root["imports"] as? [[String: Any]])
    #expect(imports.filter { ($0["name"] as? String) == name }.count == 1)
}

@Test("Antigravity uninstall preserves other registered plugins")
func antigravityManifestPreservesOthers() throws {
    let name = AntigravityHookInstaller.pluginDirectoryName
    let seeded = try JSONSerialization.data(withJSONObject: [
        "imports": [["name": "some-other-plugin", "source": "antigravity", "components": ["hooks"]]]
    ])
    let added = try AntigravityHookInstaller.importManifestData(addingPlugin: name, existing: seeded)
    let removed = try AntigravityHookInstaller.importManifestData(removingPlugin: name, existing: added)
    #expect(!AntigravityHookInstaller.importManifestContains(plugin: name, data: removed))
    #expect(AntigravityHookInstaller.importManifestContains(plugin: "some-other-plugin", data: removed))
}

// MARK: - OpenCode — JS plugin + config.json registration (real temp dir)

@Test("OpenCode fresh install writes the plugin and registers it in config.json")
func openCodeFreshInstall() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: dir)
    let status = try manager.install(pluginSourceData: Data("export default async () => ({})".utf8))

    #expect(status.isInstalled)
    #expect(status.pluginFilePresent)
    #expect(status.pluginRegistered)
    #expect(FileManager.default.fileExists(atPath: status.pluginFileURL.path))

    let config = try decode(Data(contentsOf: status.configURL))
    let plugins = try #require(config["plugin"] as? [String])
    #expect(plugins.count == 1)
    #expect(plugins[0].hasSuffix("/open-island.js"))
}

@Test("OpenCode re-install does not duplicate the plugin registration")
func openCodeReinstallIdempotent() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: dir)
    let js = Data("export default async () => ({})".utf8)
    try manager.install(pluginSourceData: js)
    let status = try manager.install(pluginSourceData: js)

    #expect(status.isInstalled)
    let config = try decode(Data(contentsOf: status.configURL))
    let plugins = try #require(config["plugin"] as? [String])
    #expect(plugins.filter { $0.hasSuffix("/open-island.js") }.count == 1)
}

@Test("OpenCode install preserves the user's other plugins")
func openCodePreservesOtherPlugins() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let configURL = dir.appendingPathComponent("config.json")
    try JSONSerialization.data(withJSONObject: ["plugin": ["file:///opt/other-plugin.js"]])
        .write(to: configURL)

    let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: dir)
    let status = try manager.install(pluginSourceData: Data("export default async () => ({})".utf8))

    let config = try decode(Data(contentsOf: status.configURL))
    let plugins = try #require(config["plugin"] as? [String])
    #expect(plugins.contains("file:///opt/other-plugin.js"))
    #expect(plugins.contains { $0.hasSuffix("/open-island.js") })
}

@Test("OpenCode uninstall removes the plugin and registration")
func openCodeUninstall() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: dir)
    try manager.install(pluginSourceData: Data("export default async () => ({})".utf8))
    let status = try manager.uninstall()

    #expect(!status.isInstalled)
    #expect(!status.pluginFilePresent)
    #expect(!status.pluginRegistered)
}
