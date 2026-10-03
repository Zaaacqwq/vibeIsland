import Foundation

public struct OpenCodePluginInstallationStatus: Equatable, Sendable {
    public var openCodeConfigDirectory: URL
    public var pluginsDirectory: URL
    public var configURL: URL
    public var pluginFileURL: URL
    public var manifestURL: URL
    public var pluginFilePresent: Bool
    public var pluginRegistered: Bool
    public var legacyPluginFilePresent: Bool
    public var legacyPluginRegistered: Bool
    public var manifest: OpenCodePluginInstallerManifest?

    public var isInstalled: Bool {
        (pluginFilePresent && pluginRegistered)
            || (legacyPluginFilePresent && legacyPluginRegistered)
    }

    public init(
        openCodeConfigDirectory: URL,
        pluginsDirectory: URL,
        configURL: URL,
        pluginFileURL: URL,
        manifestURL: URL,
        pluginFilePresent: Bool,
        pluginRegistered: Bool,
        legacyPluginFilePresent: Bool,
        legacyPluginRegistered: Bool,
        manifest: OpenCodePluginInstallerManifest?
    ) {
        self.openCodeConfigDirectory = openCodeConfigDirectory
        self.pluginsDirectory = pluginsDirectory
        self.configURL = configURL
        self.pluginFileURL = pluginFileURL
        self.manifestURL = manifestURL
        self.pluginFilePresent = pluginFilePresent
        self.pluginRegistered = pluginRegistered
        self.legacyPluginFilePresent = legacyPluginFilePresent
        self.legacyPluginRegistered = legacyPluginRegistered
        self.manifest = manifest
    }
}

public struct OpenCodePluginInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "vibe-island-opencode-plugin-install.json"

    public var pluginPath: String
    public var installedAt: Date

    public init(pluginPath: String, installedAt: Date = .now) {
        self.pluginPath = pluginPath
        self.installedAt = installedAt
    }
}

public final class OpenCodePluginInstallationManager: @unchecked Sendable {
    public static let pluginFileName = "vibe-island.js"
    private static let legacyPluginFileName = "open-island.js"
    private static let legacyManifestFileName = "open-island-opencode-plugin-install.json"

    public let openCodeConfigDirectory: URL
    private let fileManager: FileManager

    public init(
        openCodeConfigDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.openCodeConfigDirectory = openCodeConfigDirectory
        self.fileManager = fileManager
    }

    private var pluginsDirectory: URL {
        openCodeConfigDirectory.appendingPathComponent("plugins", isDirectory: true)
    }

    private var pluginFileURL: URL {
        pluginsDirectory.appendingPathComponent(Self.pluginFileName)
    }

    private var legacyPluginFileURL: URL {
        pluginsDirectory.appendingPathComponent(Self.legacyPluginFileName)
    }

    private var configURL: URL {
        openCodeConfigDirectory.appendingPathComponent("config.json")
    }

    private var manifestURL: URL {
        openCodeConfigDirectory.appendingPathComponent(OpenCodePluginInstallerManifest.fileName)
    }

    public func status() throws -> OpenCodePluginInstallationStatus {
        let pluginPresent = fileManager.fileExists(atPath: pluginFileURL.path)
        let registered = isPluginRegistered()
        let legacyPresent = legacyPluginBelongsToVibeIsland()
        let legacyRegistered = legacyPresent && isPluginRegistered(reference: "file://\(legacyPluginFileURL.path)")
        let manifest = try loadManifest()

        return OpenCodePluginInstallationStatus(
            openCodeConfigDirectory: openCodeConfigDirectory,
            pluginsDirectory: pluginsDirectory,
            configURL: configURL,
            pluginFileURL: pluginFileURL,
            manifestURL: manifestURL,
            pluginFilePresent: pluginPresent,
            pluginRegistered: registered,
            legacyPluginFilePresent: legacyPresent,
            legacyPluginRegistered: legacyRegistered,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(pluginSourceData: Data) throws -> OpenCodePluginInstallationStatus {
        let ownsLegacyPlugin = legacyPluginBelongsToVibeIsland()
        try fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)

        // Write the JS plugin file
        try pluginSourceData.write(to: pluginFileURL, options: .atomic)

        // Register in config.json
        try registerPluginInConfig(removeLegacyPlugin: ownsLegacyPlugin)

        // Write manifest
        let manifest = OpenCodePluginInstallerManifest(pluginPath: pluginFileURL.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        if ownsLegacyPlugin {
            try removeLegacyPluginFiles()
        }

        return try status()
    }

    @discardableResult
    public func uninstall() throws -> OpenCodePluginInstallationStatus {
        let ownsLegacyPlugin = legacyPluginBelongsToVibeIsland()
        // Remove plugin file
        if fileManager.fileExists(atPath: pluginFileURL.path) {
            try fileManager.removeItem(at: pluginFileURL)
        }

        // Remove from config.json
        try unregisterPluginFromConfig(removeLegacyPlugin: ownsLegacyPlugin)

        // Remove manifest
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        if ownsLegacyPlugin {
            try removeLegacyPluginFiles()
        }

        return try status()
    }

    // MARK: - Config.json manipulation

    private func pluginFileReference() -> String {
        "file://\(pluginFileURL.path)"
    }

    private func isPluginRegistered() -> Bool {
        isPluginRegistered(reference: pluginFileReference())
    }

    private func isPluginRegistered(reference: String) -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugin"] as? [String] else {
            return false
        }
        return plugins.contains(reference)
    }

    private func registerPluginInConfig(removeLegacyPlugin: Bool) throws {
        let ref = pluginFileReference()

        var json: [String: Any]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        } else {
            json = [:]
        }

        var plugins = (json["plugin"] as? [String]) ?? []

        // Replace our plugin registration and migrate an owned legacy one.
        plugins.removeAll {
            $0 == ref || $0.hasSuffix("/\(Self.pluginFileName)")
                || (removeLegacyPlugin && $0 == "file://\(legacyPluginFileURL.path)")
        }
        plugins.append(ref)

        json["plugin"] = plugins

        if fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        let outputData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: configURL, options: .atomic)
    }

    private func unregisterPluginFromConfig(removeLegacyPlugin: Bool) throws {
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var plugins = json["plugin"] as? [String] else {
            return
        }

        let ref = pluginFileReference()
        let before = plugins.count
        plugins.removeAll {
            $0 == ref || $0.hasSuffix("/\(Self.pluginFileName)")
                || (removeLegacyPlugin && $0 == "file://\(legacyPluginFileURL.path)")
        }

        guard plugins.count != before else {
            return
        }

        if fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if plugins.isEmpty {
            json.removeValue(forKey: "plugin")
        } else {
            json["plugin"] = plugins
        }

        let outputData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: configURL, options: .atomic)
    }

    // MARK: - Helpers

    private func legacyPluginBelongsToVibeIsland() -> Bool {
        guard let source = try? String(contentsOf: legacyPluginFileURL, encoding: .utf8) else {
            return false
        }
        return source.contains("Library/Application Support/VibeIsland/agent-bridge.sock")
    }

    private func removeLegacyPluginFiles() throws {
        if fileManager.fileExists(atPath: legacyPluginFileURL.path) {
            try fileManager.removeItem(at: legacyPluginFileURL)
        }
        let legacyManifestURL = openCodeConfigDirectory.appendingPathComponent(Self.legacyManifestFileName)
        if fileManager.fileExists(atPath: legacyManifestURL.path) {
            try fileManager.removeItem(at: legacyManifestURL)
        }
    }

    private func loadManifest() throws -> OpenCodePluginInstallerManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OpenCodePluginInstallerManifest.self, from: data)
    }

    private func backupFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.appendingPathExtension("backup.\(timestamp)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: url, to: backupURL)
    }
}
