import Foundation
import OpenIslandCore
import Testing
import VibeIslandAgentKit

private struct HookFixture {
    let root: URL
    let bundledBinary: URL
    let managedBinary: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-island-hook-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        bundledBinary = root.appendingPathComponent("OpenIslandHooks")
        managedBinary = root.appendingPathComponent("VibeIsland/VibeIslandAgentHooks")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bundledBinary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledBinary.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func jsonText(at url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
        .replacingOccurrences(of: "\\/", with: "/")
}

@Test("Claude hooks install, reinstall, and uninstall without removing user hooks")
func claudeManagedHookLifecycle() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let directory = fixture.root.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settings = directory.appendingPathComponent("settings.json")
    try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/user-hook"}]}]}}"#.utf8).write(to: settings)
    let configuration = VibeIslandAgentConfiguration(
        socketURL: fixture.root.appendingPathComponent("bridge.sock"),
        managedBinaryURL: fixture.managedBinary
    )
    let manager = VibeIslandClaudeHookInstaller(configuration: configuration, claudeDirectory: directory)
    #expect(try manager.install(bundledBinaryURL: fixture.bundledBinary).managedHooksPresent)
    #expect(try manager.install(bundledBinaryURL: fixture.bundledBinary).managedHooksPresent)
    #expect(try !manager.uninstall().managedHooksPresent)
    let contents = try jsonText(at: settings)
    #expect(contents.contains("/usr/bin/user-hook"))
    #expect(!contents.contains(fixture.managedBinary.path))
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(ClaudeHookInstallerManifest.fileName).path))
}

@Test("Codex hooks and trust entries are removed on uninstall")
func codexManagedHookLifecycle() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let manager = CodexHookInstallationManager(
        codexDirectory: fixture.root.appendingPathComponent(".codex"),
        managedHooksBinaryURL: fixture.managedBinary,
        featureKeyProvider: { .current }
    )
    #expect(try manager.install(hooksBinaryURL: fixture.bundledBinary).managedHooksActive)
    #expect(try manager.install(hooksBinaryURL: fixture.bundledBinary).managedHooksActive)
    let removed = try manager.uninstall()
    #expect(!removed.managedHooksPresent)
    #expect(!removed.managedHooksTrusted)
    #expect(!FileManager.default.fileExists(atPath: removed.manifestURL.path))
    let config = try String(contentsOf: removed.configURL, encoding: .utf8)
    #expect(!config.contains("[hooks.state."))
}

@Test("Gemini hooks install, reinstall, and uninstall without removing user settings")
func geminiManagedHookLifecycle() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let directory = fixture.root.appendingPathComponent(".gemini")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settings = directory.appendingPathComponent("settings.json")
    try Data(#"{"theme":"dark"}"#.utf8).write(to: settings)
    let manager = GeminiHookInstallationManager(geminiDirectory: directory, managedHooksBinaryURL: fixture.managedBinary)
    #expect(try manager.install(hooksBinaryURL: fixture.bundledBinary).managedHooksPresent)
    #expect(try manager.install(hooksBinaryURL: fixture.bundledBinary).managedHooksPresent)
    let removed = try manager.uninstall()
    #expect(!removed.managedHooksPresent)
    #expect(!FileManager.default.fileExists(atPath: removed.manifestURL.path))
    let contents = try jsonText(at: settings)
    #expect(contents.contains("dark"))
    #expect(!contents.contains(fixture.managedBinary.path))
}

@Test("Cursor hooks install, reinstall, and uninstall without removing user hooks")
func cursorManagedHookLifecycle() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let directory = fixture.root.appendingPathComponent(".cursor")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let hooks = directory.appendingPathComponent("hooks.json")
    try Data(#"{"version":1,"hooks":{"stop":[{"command":"/usr/bin/user-hook"}]}}"#.utf8).write(to: hooks)
    let manager = CursorHookInstallationManager(cursorDirectory: directory, managedHooksBinaryURL: fixture.managedBinary)
    #expect(try manager.install(hooksBinaryURL: fixture.bundledBinary).managedHooksPresent)
    #expect(try manager.install(hooksBinaryURL: fixture.bundledBinary).managedHooksPresent)
    let removed = try manager.uninstall()
    #expect(!removed.managedHooksPresent)
    #expect(!FileManager.default.fileExists(atPath: removed.manifestURL.path))
    let contents = try jsonText(at: hooks)
    #expect(contents.contains("/usr/bin/user-hook"))
    #expect(!contents.contains(fixture.managedBinary.path))
}

@Test("Antigravity plugin install, reinstall, and uninstall preserves other plugins")
func antigravityManagedHookLifecycle() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let config = fixture.root.appendingPathComponent(".gemini/config")
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    let registry = config.appendingPathComponent("import_manifest.json")
    try Data(#"{"imports":[{"name":"other","source":"antigravity","components":["hooks"]}]}"#.utf8).write(to: registry)
    let manager = AntigravityHookInstallationManager(
        pluginsDirectory: config.appendingPathComponent("plugins"),
        managedHooksBinaryURL: fixture.managedBinary
    )
    #expect(try manager.install(hooksBinaryURL: fixture.bundledBinary).managedHooksPresent)
    #expect(try manager.install(hooksBinaryURL: fixture.bundledBinary).managedHooksPresent)
    let removed = try manager.uninstall()
    #expect(!removed.managedHooksPresent)
    #expect(!FileManager.default.fileExists(atPath: removed.pluginDirectory.path))
    let registryData = try Data(contentsOf: registry)
    #expect(AntigravityHookInstaller.importManifestContains(plugin: "other", data: registryData))
    #expect(!AntigravityHookInstaller.importManifestContains(plugin: AntigravityHookInstaller.pluginDirectoryName, data: registryData))
}

@Test("OpenCode plugin install, reinstall, and uninstall preserves other plugins")
func openCodeManagedPluginLifecycle() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let directory = fixture.root.appendingPathComponent(".config/opencode")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let config = directory.appendingPathComponent("config.json")
    try Data(#"{"plugin":["file:///opt/other-plugin.js"]}"#.utf8).write(to: config)
    let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: directory)
    let source = Data("export default async () => ({});".utf8)
    #expect(try manager.install(pluginSourceData: source).isInstalled)
    #expect(try manager.install(pluginSourceData: source).isInstalled)
    let removed = try manager.uninstall()
    #expect(!removed.isInstalled)
    #expect(!removed.pluginFilePresent)
    #expect(!removed.pluginRegistered)
    #expect(!FileManager.default.fileExists(atPath: removed.manifestURL.path))
    let contents = try jsonText(at: config)
    #expect(contents.contains("file:///opt/other-plugin.js"))
}

@Test("OpenCode install and uninstall leave a standalone OpenIsland plugin intact")
func openCodePreservesStandalonePlugin() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let directory = fixture.root.appendingPathComponent(".config/opencode")
    let plugins = directory.appendingPathComponent("plugins")
    try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
    let standalone = plugins.appendingPathComponent("open-island.js")
    try Data("// OpenIsland standalone plugin".utf8).write(to: standalone)
    let config = directory.appendingPathComponent("config.json")
    let standaloneReference = "file://\(standalone.path)"
    let configData = try JSONSerialization.data(withJSONObject: ["plugin": [standaloneReference]])
    try configData.write(to: config)

    let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: directory)
    #expect(try !manager.status().isInstalled)
    #expect(try manager.install(pluginSourceData: Data("// VibeIsland plugin".utf8)).isInstalled)
    let installedConfig = try jsonText(at: config)
    #expect(installedConfig.contains(standaloneReference))
    #expect(installedConfig.contains("vibe-island.js"))

    #expect(try !manager.uninstall().isInstalled)
    #expect(FileManager.default.fileExists(atPath: standalone.path))
    let remainingConfig = try jsonText(at: config)
    #expect(remainingConfig.contains(standaloneReference))
    #expect(!remainingConfig.contains("vibe-island.js"))
}

@Test("OpenCode install migrates an older VibeIsland plugin and cleans its files")
func openCodeMigratesOwnedLegacyPlugin() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let directory = fixture.root.appendingPathComponent(".config/opencode")
    let plugins = directory.appendingPathComponent("plugins")
    try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
    let legacy = plugins.appendingPathComponent("open-island.js")
    try Data("// Library/Application Support/VibeIsland/agent-bridge.sock".utf8).write(to: legacy)
    let config = directory.appendingPathComponent("config.json")
    let configData = try JSONSerialization.data(withJSONObject: ["plugin": ["file://\(legacy.path)"]])
    try configData.write(to: config)
    let legacyManifest = directory.appendingPathComponent("open-island-opencode-plugin-install.json")
    try Data("{}".utf8).write(to: legacyManifest)

    let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: directory)
    #expect(try manager.status().isInstalled)
    #expect(try manager.install(pluginSourceData: Data("// VibeIsland plugin".utf8)).isInstalled)
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(!FileManager.default.fileExists(atPath: legacyManifest.path))
    let installedConfig = try jsonText(at: config)
    #expect(!installedConfig.contains("open-island.js"))
    #expect(installedConfig.contains("vibe-island.js"))
    #expect(try !manager.uninstall().isInstalled)
}

@Test("OpenCode can remove an older VibeIsland plugin before reinstalling")
func openCodeUninstallsOwnedLegacyPlugin() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let directory = fixture.root.appendingPathComponent(".config/opencode")
    let plugins = directory.appendingPathComponent("plugins")
    try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
    let legacy = plugins.appendingPathComponent("open-island.js")
    try Data("// Library/Application Support/VibeIsland/agent-bridge.sock".utf8).write(to: legacy)
    let config = directory.appendingPathComponent("config.json")
    let configData = try JSONSerialization.data(withJSONObject: ["plugin": ["file://\(legacy.path)"]])
    try configData.write(to: config)

    let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: directory)
    #expect(try manager.status().isInstalled)
    #expect(try !manager.uninstall().isInstalled)
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(!(try jsonText(at: config)).contains("open-island.js"))
}

@Test("Pi extension install, reinstall, and uninstall removes its manifest")
func piManagedExtensionLifecycle() throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let manager = PiExtensionInstallationManager(agent: .pi, agentDirectory: fixture.root.appendingPathComponent(".pi/agent"))
    let source = Data("const agent = '__OPEN_ISLAND_PI_SOURCE__';".utf8)
    #expect(try manager.install(extensionSourceData: source).isCurrent)
    #expect(try manager.install(extensionSourceData: source).isCurrent)
    let removed = try manager.uninstall()
    #expect(!removed.isInstalled)
    #expect(!removed.extensionFilePresent)
    #expect(!FileManager.default.fileExists(atPath: removed.manifestURL.path))
}

@Test("Several hook providers can install concurrently using one managed binary")
func concurrentManagedHookInstall() async throws {
    let fixture = try HookFixture()
    defer { fixture.remove() }
    let binary = fixture.bundledBinary
    let managed = fixture.managedBinary
    let root = fixture.root

    let codex = CodexHookInstallationManager(
        codexDirectory: root.appendingPathComponent(".codex"),
        managedHooksBinaryURL: managed,
        featureKeyProvider: { .current }
    )
    let cursor = CursorHookInstallationManager(
        cursorDirectory: root.appendingPathComponent(".cursor"),
        managedHooksBinaryURL: managed
    )
    let gemini = GeminiHookInstallationManager(
        geminiDirectory: root.appendingPathComponent(".gemini"),
        managedHooksBinaryURL: managed
    )
    let antigravity = AntigravityHookInstallationManager(
        pluginsDirectory: root.appendingPathComponent(".gemini/config/plugins"),
        managedHooksBinaryURL: managed
    )

    try await withThrowingTaskGroup(of: Bool.self) { group in
        group.addTask { try codex.install(hooksBinaryURL: binary).managedHooksActive }
        group.addTask { try cursor.install(hooksBinaryURL: binary).managedHooksPresent }
        group.addTask { try gemini.install(hooksBinaryURL: binary).managedHooksPresent }
        group.addTask { try antigravity.install(hooksBinaryURL: binary).managedHooksPresent }
        for try await installed in group { #expect(installed) }
    }
    #expect(try Data(contentsOf: managed) == Data(contentsOf: binary))
}
