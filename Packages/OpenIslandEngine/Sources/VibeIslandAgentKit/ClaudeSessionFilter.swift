import Foundation
import OpenIslandCore

/// Scope filter for which agents VibeIsland surfaces in the notch. Claude Code
/// and its hook-compatible forks (Qoder, Qwen Code, Factory, CodeBuddy, Kimi),
/// plus Codex and Gemini CLI which have their own hook payloads but are fully
/// wired through the bridge. OpenCode (plugin-based) and Cursor are not surfaced
/// yet — they flow through the engine but aren't displayed.
public enum ClaudeSessionFilter {
    /// Tools VibeIsland currently displays.
    public static func includes(_ tool: AgentTool) -> Bool {
        switch tool {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI, .codex, .geminiCLI, .antigravity:
            true
        case .openCode, .cursor:
            false
        }
    }

    /// Claude-family sessions from a state snapshot, preserving the engine's
    /// own ordering (`SessionState.sessions`).
    public static func claudeSessions(in state: SessionState) -> [AgentSession] {
        state.sessions.filter { includes($0.tool) }
    }
}
