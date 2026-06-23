import Foundation

/// Primitives for installing Antigravity CLI (`agy`) hooks.
///
/// Antigravity does NOT read hooks from `settings.json` like Claude/Gemini.
/// Instead it loads them from a *plugin* directory
/// (`~/.gemini/config/plugins/<name>/` with a `plugin.json` manifest pointing
/// at a `hooks.json`) AND requires the plugin to be registered in
/// `~/.gemini/config/import_manifest.json`. Each event registers a distinct
/// command because the stdin payload carries no event name — the event is
/// encoded in `--event`.
public enum AntigravityHookInstaller {
    /// Folder name created under the plugins directory.
    public static let pluginDirectoryName = "vibeisland"

    /// Events the plugin registers. `Stop` is Antigravity's turn-complete
    /// signal (the "agent finished responding" analog of Claude's Stop).
    public static let events: [AntigravityHookEventName] = [
        .sessionStart, .preToolUse, .postToolUse, .stop, .sessionEnd, .notification
    ]

    /// Substring that identifies any Open Island / VibeIsland managed command
    /// regardless of the exact binary path.
    public static let managedCommandMarker = "--source antigravity"

    /// Hook command for an event. No socket override prefix is needed: the
    /// engine's default bridge socket already resolves to VibeIsland's, same as
    /// the Codex/Gemini installers.
    public static func hookCommand(for binaryPath: String, event: AntigravityHookEventName) -> String {
        "\(shellQuote(binaryPath)) --source antigravity --event \(event.rawValue)"
    }

    /// Builds the `hooks.json` body, one managed command per event.
    public static func hooksFileData(binaryPath: String) throws -> Data {
        var hooks: [String: Any] = [:]
        for event in events {
            let handler: [String: Any] = [
                "type": "command",
                "command": hookCommand(for: binaryPath, event: event)
            ]
            hooks[event.rawValue] = [["hooks": [handler]]]
        }
        return try JSONSerialization.data(
            withJSONObject: ["hooks": hooks],
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    public static func pluginManifestData(
        name: String,
        version: String,
        description: String
    ) throws -> Data {
        let manifest: [String: Any] = [
            "name": name,
            "version": version,
            "description": description,
            "hooks": "./hooks.json"
        ]
        return try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    /// Whether a `hooks.json` body contains our managed hook command.
    public static func hooksFileContainsManagedCommand(
        data: Data?,
        marker: String = managedCommandMarker
    ) -> Bool {
        guard let data, let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains(marker)
    }

    // MARK: - Plugin registry (import_manifest.json)

    /// Antigravity only loads plugins listed in `import_manifest.json`. These
    /// helpers merge/remove our entry while preserving other registered plugins.
    public static func importManifestData(
        addingPlugin name: String,
        existing: Data?,
        importedAt: Date = Date()
    ) throws -> Data {
        var root = decodeManifestRoot(existing)
        var imports = (root["imports"] as? [[String: Any]]) ?? []
        imports.removeAll { ($0["name"] as? String) == name }
        imports.append([
            "name": name,
            "source": "antigravity",
            "importedAt": isoString(from: importedAt),
            "components": ["hooks"]
        ])
        root["imports"] = imports
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Removes our plugin entry; returns `nil` when the manifest becomes empty
    /// (caller may delete the file).
    public static func importManifestData(
        removingPlugin name: String,
        existing: Data?
    ) throws -> Data? {
        guard let existing else { return nil }
        var root = decodeManifestRoot(existing)
        var imports = (root["imports"] as? [[String: Any]]) ?? []
        imports.removeAll { ($0["name"] as? String) == name }
        if imports.isEmpty {
            root.removeValue(forKey: "imports")
        } else {
            root["imports"] = imports
        }
        if root.isEmpty { return nil }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public static func importManifestContains(plugin name: String, data: Data?) -> Bool {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let imports = root["imports"] as? [[String: Any]] else {
            return false
        }
        return imports.contains { ($0["name"] as? String) == name }
    }

    private static func decodeManifestRoot(_ data: Data?) -> [String: Any] {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return root
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
