import Foundation

public struct GeminiHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-gemini-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct GeminiHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

public enum GeminiHookInstallerError: Error, LocalizedError {
    case invalidSettingsJSON

    public var errorDescription: String? {
        switch self {
        case .invalidSettingsJSON:
            "The existing Gemini settings.json is not valid JSON."
        }
    }
}

/// Pure JSON transformer for Gemini CLI's `~/.gemini/settings.json` hooks block.
///
/// Gemini CLI shares Claude Code's nested hook schema:
/// `hooks → <Event> → [ { "hooks": [ { "type": "command", "command": ... } ] } ]`.
/// Lifecycle events (SessionStart/SessionEnd/Notification) fire globally and take
/// no `matcher`; agent-loop events (BeforeAgent/AfterAgent) also fire globally for
/// our purposes, so we register a single managed group per event with no matcher.
public enum GeminiHookInstaller {
    /// Events the bundled `OpenIslandHooks --source gemini` binary understands
    /// (mirrors `GeminiHookEventName`).
    private static let eventNames: [String] = [
        "SessionStart",
        "SessionEnd",
        "BeforeAgent",
        "AfterAgent",
        "Notification",
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source gemini"
    }

    public static func installSettingsJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> GeminiHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]

        for eventName in eventNames {
            let existingGroups = hooksObject[eventName] as? [Any] ?? []
            let cleanedGroups = sanitize(groups: existingGroups, managedCommand: hookCommand)
            hooksObject[eventName] = cleanedGroups + [managedGroup(hookCommand: hookCommand)]
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)

        return GeminiHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallSettingsJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> GeminiHookFileMutation {
        guard let existingData else {
            return GeminiHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var mutated = false

        for eventName in eventNames {
            let existingGroups = hooksObject[eventName] as? [Any] ?? []
            let cleanedGroups = sanitize(groups: existingGroups, managedCommand: managedCommand)

            if cleanedGroups.count != existingGroups.count
                || containsManagedHook(in: existingGroups, managedCommand: managedCommand) {
                mutated = true
            }

            if cleanedGroups.isEmpty {
                hooksObject.removeValue(forKey: eventName)
            } else {
                hooksObject[eventName] = cleanedGroups
            }
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return GeminiHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated
        )
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw GeminiHookInstallerError.invalidSettingsJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func sanitize(groups: [Any], managedCommand: String?) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else { return nil }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else { return nil }
                return isManagedHook(hook, managedCommand: managedCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else { return nil }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func containsManagedHook(in groups: [Any], managedCommand: String?) -> Bool {
        groups.contains { item in
            guard let group = item as? [String: Any],
                  let hooks = group["hooks"] as? [Any] else {
                return false
            }

            return hooks.contains { hook in
                guard let hook = hook as? [String: Any] else { return false }
                return isManagedHook(hook, managedCommand: managedCommand)
            }
        }
    }

    private static func managedGroup(hookCommand: String) -> [String: Any] {
        [
            "hooks": [
                [
                    "type": "command",
                    "command": hookCommand,
                ],
            ],
        ]
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        guard let command = hook["command"] as? String else { return false }

        if let managedCommand, command == managedCommand {
            return true
        }

        return isOpenIslandGeminiHookCommand(command)
    }

    private static func isOpenIslandGeminiHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        guard normalized.contains("--source gemini") else { return false }
        // Current managed binary names plus legacy hyphenated launcher names so a
        // reinstall cleans up stale entries instead of stacking duplicates.
        return normalized.contains("openislandhooks")
            || normalized.contains("vibeislandhooks")
            || normalized.contains("open-island-bridge")
            || normalized.contains("vibe-island-bridge")
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
