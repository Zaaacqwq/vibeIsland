import Foundation
import OpenIslandCore

/// Scope filter for which agents VibeIsland surfaces in the notch. Claude Code
/// and its hook-compatible forks (Qoder, Qwen Code, Factory, CodeBuddy, Kimi),
/// plus Codex, Gemini CLI, Antigravity, OpenCode (plugin-based), and Cursor —
/// all have their own hook payloads and are fully wired through the bridge.
public enum ClaudeSessionFilter {
    /// Tools VibeIsland currently displays.
    public static func includes(_ tool: AgentTool) -> Bool {
        switch tool {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI, .codex, .geminiCLI, .antigravity, .openCode, .cursor:
            true
        }
    }

    /// Claude-family sessions from a state snapshot, preserving the engine's
    /// own ordering (`SessionState.sessions`).
    public static func claudeSessions(in state: SessionState) -> [AgentSession] {
        state.sessions.filter { includes($0.tool) }
    }
}
