import Foundation

public struct AntigravityHookInstallationStatus: Equatable, Sendable {
    public var pluginDirectory: URL
    public var hooksFileURL: URL
    public var importManifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool

    public init(
        pluginDirectory: URL,
        hooksFileURL: URL,
        importManifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool
    ) {
        self.pluginDirectory = pluginDirectory
        self.hooksFileURL = hooksFileURL
        self.importManifestURL = importManifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
    }
}

/// Installs Antigravity CLI (`agy`) hooks as a registered plugin. Mirrors
/// `GeminiHookInstallationManager`'s shape so the app can drive it the same way,
/// but writes a plugin directory + registers it in `import_manifest.json`
/// instead of mutating a `settings.json`.
public final class AntigravityHookInstallationManager: @unchecked Sendable {
    /// `~/.gemini/config/plugins` — where Antigravity discovers plugins.
    public let pluginsDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        pluginsDirectory: URL = AntigravityHookInstallationManager.defaultPluginsDirectory,
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.pluginsDirectory = pluginsDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public static var defaultPluginsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/config/plugins", isDirectory: true)
    }

    private var pluginDirectory: URL {
        pluginsDirectory.appendingPathComponent(AntigravityHookInstaller.pluginDirectoryName, isDirectory: true)
    }

    private var manifestFileURL: URL { pluginDirectory.appendingPathComponent("plugin.json") }
    private var hooksFileURL: URL { pluginDirectory.appendingPathComponent("hooks.json") }

    /// `~/.gemini/config/import_manifest.json` — the plugin registry, alongside
    /// the `plugins/` folder.
    private var importManifestURL: URL {
        pluginsDirectory.deletingLastPathComponent().appendingPathComponent("import_manifest.json")
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> AntigravityHookInstallationStatus {
        let hooksData = try? Data(contentsOf: hooksFileURL)
        let registryData = try? Data(contentsOf: importManifestURL)
        // Both must hold: the hook command is written AND the plugin is
        // registered (Antigravity ignores unregistered plugins).
        let present = AntigravityHookInstaller.hooksFileContainsManagedCommand(data: hooksData)
            && AntigravityHookInstaller.importManifestContains(
                plugin: AntigravityHookInstaller.pluginDirectoryName,
                data: registryData
            )
        return AntigravityHookInstallationStatus(
            pluginDirectory: pluginDirectory,
            hooksFileURL: hooksFileURL,
            importManifestURL: importManifestURL,
            hooksBinaryURL: resolvedHooksBinaryURL(explicitURL: hooksBinaryURL),
            managedHooksPresent: present
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> AntigravityHookInstallationStatus {
        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )

        try fileManager.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)

        let manifest = try AntigravityHookInstaller.pluginManifestData(
            name: AntigravityHookInstaller.pluginDirectoryName,
            version: "0.1.0",
            description: "VibeIsland agent monitoring for Antigravity CLI (agy)."
        )
        try manifest.write(to: manifestFileURL, options: .atomic)

        let hooks = try AntigravityHookInstaller.hooksFileData(binaryPath: installedBinaryURL.path)
        try hooks.write(to: hooksFileURL, options: .atomic)

        // Register the plugin so Antigravity actually loads it.
        try fileManager.createDirectory(
            at: importManifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let registry = try AntigravityHookInstaller.importManifestData(
            addingPlugin: AntigravityHookInstaller.pluginDirectoryName,
            existing: try? Data(contentsOf: importManifestURL)
        )
        try registry.write(to: importManifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> AntigravityHookInstallationStatus {
        if fileManager.fileExists(atPath: pluginDirectory.path) {
            try fileManager.removeItem(at: pluginDirectory)
        }

        if let existing = try? Data(contentsOf: importManifestURL) {
            let updated = try AntigravityHookInstaller.importManifestData(
                removingPlugin: AntigravityHookInstaller.pluginDirectoryName,
                existing: existing
            )
            if let updated {
                try updated.write(to: importManifestURL, options: .atomic)
            } else if fileManager.fileExists(atPath: importManifestURL.path) {
                try fileManager.removeItem(at: importManifestURL)
            }
        }

        return try status()
    }

    private func resolvedHooksBinaryURL(explicitURL: URL?) -> URL? {
        if let explicitURL {
            return explicitURL.standardizedFileURL
        }
        guard fileManager.isExecutableFile(atPath: managedHooksBinaryURL.path) else {
            return nil
        }
        return managedHooksBinaryURL
    }
}
