import Foundation
import OpenIslandCore

/// Installs Atoll's Claude Code hooks. Reuses the engine's settings.json
/// mutation and manifest primitives but supplies an Atoll-namespaced hook
/// command (socket override + managed binary path) so it never disturbs a
/// standalone Open Island install.
///
/// `status` and `uninstall` delegate to the engine's
/// `ClaudeHookInstallationManager`, which keys off the manifest's stored
/// command — so removal matches whatever this installer wrote.
public struct AtollClaudeHookInstaller {
    private let configuration: AtollAgentConfiguration
    private let claudeDirectory: URL
    private let fileManager: FileManager

    public init(
        configuration: AtollAgentConfiguration = AtollAgentConfiguration(),
        claudeDirectory: URL = ClaudeConfigDirectory.resolved(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.claudeDirectory = claudeDirectory
        self.fileManager = fileManager
    }

    private var manager: ClaudeHookInstallationManager {
        ClaudeHookInstallationManager(
            claudeDirectory: claudeDirectory,
            managedHooksBinaryURL: configuration.managedBinaryURL,
            hookSource: AtollAgentConfiguration.hookSource,
            fileManager: fileManager
        )
    }

    /// Copies the bundled hooks binary into Atoll's managed location and writes
    /// the namespaced hook command into Claude's `settings.json`.
    /// - Parameter bundledBinaryURL: the `OpenIslandHooks` binary shipped inside
    ///   `Atoll.app/Contents/Helpers`.
    @discardableResult
    public func install(bundledBinaryURL: URL) throws -> ClaudeHookInstallationStatus {
        try fileManager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let installedBinaryURL = try ManagedHooksBinary.install(
            from: bundledBinaryURL,
            to: configuration.managedBinaryURL,
            fileManager: fileManager
        )

        let command = configuration.hookCommand(binaryPath: installedBinaryURL.path)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let existingSettings = try? Data(contentsOf: settingsURL)
        let mutation = try ClaudeHookInstaller.installSettingsJSON(
            existingData: existingSettings,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: settingsURL.path) {
            try backupFile(at: settingsURL)
        }
        if let contents = mutation.contents {
            try contents.write(to: settingsURL, options: .atomic)
        }

        try writeManifest(command: command)
        return try status()
    }

    public func status() throws -> ClaudeHookInstallationStatus {
        try manager.status(hooksBinaryURL: configuration.managedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> ClaudeHookInstallationStatus {
        try manager.uninstall()
    }

    private func writeManifest(command: String) throws {
        let manifestURL = claudeDirectory.appendingPathComponent(ClaudeHookInstallerManifest.fileName)
        let manifest = ClaudeHookInstallerManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private func backupFile(at url: URL) throws {
        let backupURL = url.appendingPathExtension("atoll-backup")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: url, to: backupURL)
    }
}
