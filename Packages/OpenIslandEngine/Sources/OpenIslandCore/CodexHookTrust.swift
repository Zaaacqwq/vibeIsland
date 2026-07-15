import CryptoKit
import Foundation

public struct CodexHookTrustEntry: Equatable, Sendable {
    public var key: String
    public var trustedHash: String

    public init(key: String, trustedHash: String) {
        self.key = key
        self.trustedHash = trustedHash
    }
}

public struct CodexHookTrustMutation: Equatable, Sendable {
    public var contents: String
    public var changed: Bool

    public init(contents: String, changed: Bool) {
        self.contents = contents
        self.changed = changed
    }
}

/// Mirrors Codex CLI's persisted hook-trust state (`[hooks.state."…"]` in
/// `config.toml`). Since codex-cli 0.130+, user-level hooks that are not
/// marked trusted are discovered but never executed, so installing our
/// managed hooks without also persisting their trust entries leaves them
/// inert until the user approves them in the Codex TUI.
///
/// Key and hash formats must stay byte-compatible with codex-rs:
/// - key:  `<hooks.json path>:<snake_case event>:<group index>:<hook index>`
/// - hash: sha256 over the canonical JSON (sorted keys, compact separators,
///   unescaped non-ASCII) of the normalized hook identity.
public enum CodexHookTrust {
    /// Persisted state labels per event, matching codex-rs `hook_event_key_label`.
    static let eventKeyLabels: [String: String] = [
        "PreToolUse": "pre_tool_use",
        "PermissionRequest": "permission_request",
        "PostToolUse": "post_tool_use",
        "PreCompact": "pre_compact",
        "PostCompact": "post_compact",
        "SessionStart": "session_start",
        "UserPromptSubmit": "user_prompt_submit",
        "SubagentStart": "subagent_start",
        "SubagentStop": "subagent_stop",
        "Stop": "stop",
    ]

    /// Events whose matcher Codex ignores during dispatch; it is also dropped
    /// from the trust-hash identity (codex-rs `matcher_pattern_for_event`).
    private static let matcherlessEvents: Set<String> = ["UserPromptSubmit", "Stop"]

    private static let sectionPrefix = "[hooks.state.\""
    private static let sectionSuffix = "\"]"

    // MARK: - Entry computation

    /// Trust entries for every managed hook found in a hooks.json payload.
    /// `includeLegacyCommands` additionally matches stale OpenIsland/VibeIsland
    /// commands that (re)install scrubs, so their trust entries can be removed
    /// alongside the hooks themselves.
    public static func managedEntries(
        hooksData: Data?,
        hooksFilePath: String,
        managedCommand: String?,
        includeLegacyCommands: Bool = false
    ) -> [CodexHookTrustEntry] {
        guard let hooksData,
              let root = (try? JSONSerialization.jsonObject(with: hooksData)) as? [String: Any],
              let hooksObject = root["hooks"] as? [String: Any] else {
            return []
        }

        var entries: [CodexHookTrustEntry] = []
        for (eventName, value) in hooksObject {
            guard let label = eventKeyLabels[eventName], let groups = value as? [Any] else {
                continue
            }

            for (groupIndex, groupValue) in groups.enumerated() {
                guard let group = groupValue as? [String: Any] else {
                    continue
                }

                let matcher = group["matcher"] as? String
                let hooks = group["hooks"] as? [Any] ?? []
                for (hookIndex, hookValue) in hooks.enumerated() {
                    guard let hook = hookValue as? [String: Any],
                          isManagedForTrust(
                              hook,
                              managedCommand: managedCommand,
                              includeLegacyCommands: includeLegacyCommands
                          ),
                          let hash = trustHash(eventName: eventName, matcher: matcher, hook: hook) else {
                        continue
                    }

                    entries.append(CodexHookTrustEntry(
                        key: "\(hooksFilePath):\(label):\(groupIndex):\(hookIndex)",
                        trustedHash: hash
                    ))
                }
            }
        }

        return entries.sorted { $0.key < $1.key }
    }

    /// Whether every managed hook in hooks.json has a matching trust entry in
    /// the Codex config. False when there are no managed hooks at all.
    public static func managedHooksTrusted(
        configContents: String,
        hooksData: Data?,
        hooksFilePath: String,
        managedCommand: String?
    ) -> Bool {
        let entries = managedEntries(
            hooksData: hooksData,
            hooksFilePath: hooksFilePath,
            managedCommand: managedCommand
        )
        guard !entries.isEmpty else {
            return false
        }

        let existing = existingEntries(in: configContents.components(separatedBy: "\n"))
        return entries.allSatisfy { existing[$0.key] == $0.trustedHash }
    }

    // MARK: - Config mutation

    /// Returns the config contents with `removingKeys` trust sections dropped
    /// and `entries` (re)written. No-op (`changed == false`) when the config
    /// already matches the requested state.
    public static func applying(
        entries: [CodexHookTrustEntry],
        removingKeys: [String],
        to contents: String
    ) -> CodexHookTrustMutation {
        let lines = contents.components(separatedBy: "\n")
        let existing = existingEntries(in: lines)
        let entryKeys = Set(entries.map(\.key))
        let converged = entries.allSatisfy { existing[$0.key] == $0.trustedHash }
            && removingKeys.allSatisfy { entryKeys.contains($0) || existing[$0] == nil }
        if converged {
            return CodexHookTrustMutation(contents: contents, changed: false)
        }

        let targetKeys = Set(removingKeys).union(entryKeys)
        var output: [String] = []
        var skippingSection = false
        for line in lines {
            if let key = sectionKey(headerLine: line) {
                skippingSection = targetKeys.contains(key)
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                skippingSection = false
            }

            if !skippingSection {
                output.append(line)
            }
        }

        while output.last?.isEmpty == true {
            output.removeLast()
        }
        for entry in entries {
            if !output.isEmpty {
                output.append("")
            }
            output.append("\(sectionPrefix)\(escapeTOMLBasicString(entry.key))\(sectionSuffix)")
            output.append("trusted_hash = \"\(entry.trustedHash)\"")
        }
        output.append("")

        let updated = output.joined(separator: "\n")
        return CodexHookTrustMutation(contents: updated, changed: updated != contents)
    }

    // MARK: - Trust hash (codex-rs `command_hook_hash` parity)

    static func trustHash(eventName: String, matcher: String?, hook: [String: Any]) -> String? {
        guard let label = eventKeyLabels[eventName],
              let command = hook["command"] as? String else {
            return nil
        }
        // Codex skips async hooks before they ever reach the hash step.
        if hook["async"] as? Bool == true {
            return nil
        }

        let timeout = max((hook["timeout"] as? NSNumber)?.int64Value ?? 600, 1)
        let statusMessage = hook["statusMessage"] as? String
        let normalizedMatcher = matcherlessEvents.contains(eventName) ? nil : matcher

        // Canonical JSON: keys sorted byte-wise, compact separators.
        var handler = "{\"async\":false,\"command\":\(jsonString(command))"
        if let statusMessage {
            handler += ",\"statusMessage\":\(jsonString(statusMessage))"
        }
        handler += ",\"timeout\":\(timeout),\"type\":\"command\"}"

        var identity = "{\"event_name\":\(jsonString(label)),\"hooks\":[\(handler)]"
        if let normalizedMatcher {
            identity += ",\"matcher\":\(jsonString(normalizedMatcher))"
        }
        identity += "}"

        let digest = SHA256.hash(data: Data(identity.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Helpers

    private static func isManagedForTrust(
        _ hook: [String: Any],
        managedCommand: String?,
        includeLegacyCommands: Bool
    ) -> Bool {
        if CodexHookInstaller.isManagedHook(hook, managedCommand: managedCommand) {
            return true
        }

        guard includeLegacyCommands, let command = hook["command"] as? String else {
            return false
        }

        return CodexHookInstaller.isLegacyOpenIslandHookCommand(command)
    }

    /// Scans line-based TOML for `[hooks.state."…"]` sections and returns
    /// each key's `trusted_hash` value (or nil when the section lacks one).
    private static func existingEntries(in lines: [String]) -> [String: String] {
        var entries: [String: String] = [:]
        var currentKey: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let key = sectionKey(headerLine: line) {
                currentKey = key
            } else if trimmed.hasPrefix("[") {
                currentKey = nil
            } else if let currentKey, let value = trustedHashValue(in: trimmed) {
                entries[currentKey] = value
            }
        }

        return entries
    }

    private static func sectionKey(headerLine: String) -> String? {
        let trimmed = headerLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(sectionPrefix), trimmed.hasSuffix(sectionSuffix) else {
            return nil
        }

        let inner = trimmed.dropFirst(sectionPrefix.count).dropLast(sectionSuffix.count)
        return unescapeTOMLBasicString(String(inner))
    }

    private static func trustedHashValue(in trimmedLine: String) -> String? {
        let parts = trimmedLine.split(separator: "=", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, parts[0] == "trusted_hash" else {
            return nil
        }

        var value = parts[1]
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return unescapeTOMLBasicString(value)
    }

    private static func escapeTOMLBasicString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func unescapeTOMLBasicString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// serde_json-compatible string encoding: escapes quotes, backslashes and
    /// control characters; leaves non-ASCII (and `/`) unescaped.
    private static func jsonString(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                output += "\\\""
            case "\\":
                output += "\\\\"
            case "\n":
                output += "\\n"
            case "\r":
                output += "\\r"
            case "\t":
                output += "\\t"
            case "\u{08}":
                output += "\\b"
            case "\u{0C}":
                output += "\\f"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        return output + "\""
    }
}
