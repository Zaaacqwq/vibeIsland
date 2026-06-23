import Foundation

/// Lifecycle events emitted by Antigravity CLI (`agy`, Google's Gemini-based
/// coding agent). Unlike Claude/Gemini, the event name is NOT part of the
/// stdin payload — the hooks CLI injects it from the `--event` argument the
/// plugin registers per event.
public enum AntigravityHookEventName: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"
    case notification = "Notification"
}

/// A single tool invocation as reported by Antigravity's Pre/PostToolUse hooks.
public struct AntigravityToolCall: Equatable, Codable, Sendable {
    public var name: String?
    public var args: CodexHookJSONValue?

    public init(name: String? = nil, args: CodexHookJSONValue? = nil) {
        self.name = name
        self.args = args
    }
}

/// Decoded stdin payload from an Antigravity CLI hook.
///
/// The on-disk JSON (`conversationId`, `workspacePaths`, `toolCall`, …) never
/// includes the event name, so `hookEventName` is decoded leniently
/// (defaulting to `.notification`) and overwritten by the CLI from `--event`
/// before the payload is forwarded over the bridge — where it round-trips
/// normally.
public struct AntigravityHookPayload: Equatable, Codable, Sendable {
    public var conversationId: String
    public var workspacePaths: [String]
    public var stepIdx: Int?
    public var toolCall: AntigravityToolCall?
    public var error: String?
    public var transcriptPath: String?
    public var artifactDirectoryPath: String?
    public var hookEventName: AntigravityHookEventName

    // Terminal context — absent from agy's payload, filled in by the CLI via
    // `withRuntimeContext` so jump-back can locate the originating terminal.
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?

    private enum CodingKeys: String, CodingKey {
        case conversationId
        case workspacePaths
        case stepIdx
        case toolCall
        case error
        case transcriptPath
        case artifactDirectoryPath
        case hookEventName
        case terminalApp
        case terminalSessionID
        case terminalTTY
        case terminalTitle
    }

    public init(
        conversationId: String,
        workspacePaths: [String] = [],
        stepIdx: Int? = nil,
        toolCall: AntigravityToolCall? = nil,
        error: String? = nil,
        transcriptPath: String? = nil,
        artifactDirectoryPath: String? = nil,
        hookEventName: AntigravityHookEventName = .notification,
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil
    ) {
        self.conversationId = conversationId
        self.workspacePaths = workspacePaths
        self.stepIdx = stepIdx
        self.toolCall = toolCall
        self.error = error
        self.transcriptPath = transcriptPath
        self.artifactDirectoryPath = artifactDirectoryPath
        self.hookEventName = hookEventName
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        workspacePaths = try container.decodeIfPresent([String].self, forKey: .workspacePaths) ?? []
        stepIdx = try container.decodeIfPresent(Int.self, forKey: .stepIdx)
        toolCall = try container.decodeIfPresent(AntigravityToolCall.self, forKey: .toolCall)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        artifactDirectoryPath = try container.decodeIfPresent(String.self, forKey: .artifactDirectoryPath)
        hookEventName = try container.decodeIfPresent(AntigravityHookEventName.self, forKey: .hookEventName) ?? .notification
        terminalApp = try container.decodeIfPresent(String.self, forKey: .terminalApp)
        terminalSessionID = try container.decodeIfPresent(String.self, forKey: .terminalSessionID)
        terminalTTY = try container.decodeIfPresent(String.self, forKey: .terminalTTY)
        terminalTitle = try container.decodeIfPresent(String.self, forKey: .terminalTitle)
    }
}

public extension AntigravityHookPayload {
    /// Antigravity addresses sessions by `conversationId`; map it onto the
    /// engine's generic session id.
    var sessionID: String { conversationId }

    var cwd: String { workspacePaths.first ?? "" }

    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd)
    }

    var sessionTitle: String {
        "Antigravity · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "Terminal",
            workspaceName: workspaceName,
            paneTitle: terminalTitle ?? "Antigravity \(conversationId.prefix(8))",
            workingDirectory: cwd,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY
        )
    }

    /// Antigravity stores per-turn artifacts and a transcript on disk; the
    /// notch reuses Gemini's metadata holder (a generic transcript/prompt
    /// record) to surface them.
    var defaultMetadata: GeminiSessionMetadata {
        GeminiSessionMetadata(transcriptPath: transcriptPath)
    }

    var implicitSummary: String {
        switch hookEventName {
        case .sessionStart:
            return "Started Antigravity session in \(workspaceName)."
        case .preToolUse:
            return toolActivitySummary ?? "Antigravity is working in \(workspaceName)."
        case .postToolUse:
            return toolActivitySummary ?? "Antigravity finished a step in \(workspaceName)."
        case .stop:
            return "Antigravity finished responding in \(workspaceName)."
        case .sessionEnd:
            return "Antigravity session ended in \(workspaceName)."
        case .notification:
            return notificationSummary
        }
    }

    var notificationSummary: String {
        toolActivitySummary ?? "Antigravity needs your attention in \(workspaceName)."
    }

    /// Human-readable description of the current tool call, preferring
    /// Antigravity's own `toolSummary`/`toolAction` over the raw command.
    var toolActivitySummary: String? {
        guard let toolCall else { return nil }
        let argString: (String) -> String? = { key in
            guard case let .object(object)? = toolCall.args,
                  case let .string(value)? = object[key],
                  !value.isEmpty else { return nil }
            return value
        }

        if let summary = argString("toolSummary") {
            return clipped(summary)
        }
        if let action = argString("toolAction") {
            return clipped(action)
        }
        if let command = argString("CommandLine") {
            return clipped("Running \(command)")
        }
        if let name = toolCall.name, !name.isEmpty {
            return "Using \(name)"
        }
        return nil
    }

    private func clipped(_ value: String, limit: Int = 110) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return "\(collapsed[..<endIndex])…"
    }

    /// Fills in terminal context from the hook process environment so the
    /// notch can offer jump-back. Lean by design (terminal app + TTY); the
    /// AppleScript pane locator used for Gemini is intentionally omitted.
    func withRuntimeContext(environment: [String: String]) -> AntigravityHookPayload {
        var payload = self
        if payload.terminalApp == nil {
            payload.terminalApp = Self.inferTerminalApp(from: environment)
        }
        if payload.terminalTTY == nil {
            payload.terminalTTY = Self.currentTTY()
        }
        return payload
    }

    private static func inferTerminalApp(from environment: [String: String]) -> String? {
        if environment["ITERM_SESSION_ID"] != nil || environment["LC_TERMINAL"] == "iTerm2" {
            return "iTerm"
        }
        if environment["GHOSTTY_RESOURCES_DIR"] != nil {
            return "Ghostty"
        }
        if environment["WARP_IS_LOCAL_SHELL_SESSION"] != nil {
            return "Warp"
        }
        switch environment["TERM_PROGRAM"]?.lowercased() {
        case .some("apple_terminal"):
            return "Terminal"
        case .some("iterm.app"), .some("iterm2"):
            return "iTerm"
        case let value? where value.contains("ghostty"):
            return "Ghostty"
        case let value? where value.contains("warp"):
            return "Warp"
        case let value? where value.contains("wezterm"):
            return "WezTerm"
        case .some("vscode"):
            return "VS Code"
        default:
            return nil
        }
    }

    private static func currentTTY() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tty")
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty, !raw.contains("not a tty") else {
            return nil
        }
        return raw
    }
}
