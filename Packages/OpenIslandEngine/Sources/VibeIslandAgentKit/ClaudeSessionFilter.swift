import Foundation
import OpenIslandCore

/// Scope filter for which agents VibeIsland surfaces in the notch. Claude Code,
/// Codex, Gemini CLI, Antigravity, OpenCode (plugin-based), and Cursor all have
/// hook payloads wired through the bridge.
public enum ClaudeSessionFilter {
    /// Tools VibeIsland currently displays.
    public static func includes(_ tool: AgentTool) -> Bool {
        switch tool {
        case .claudeCode, .codex, .geminiCLI, .antigravity, .openCode, .cursor:
            true
        }
    }

    /// Claude-family sessions from a state snapshot, preserving the engine's
    /// own ordering (`SessionState.sessions`).
    public static func claudeSessions(in state: SessionState) -> [AgentSession] {
        state.sessions.filter { includes($0.tool) }
    }
}
