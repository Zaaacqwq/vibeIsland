import Foundation
import OpenIslandCore

/// MVP scope filter: Atoll surfaces only Claude Code sessions (and its
/// hook-compatible forks — Qoder, Qwen Code, Factory, CodeBuddy, Kimi — which
/// share Claude Code's hook payload format). Other agents flow through the
/// engine but are not displayed yet.
public enum ClaudeSessionFilter {
    /// Tools that speak Claude Code's hook protocol.
    public static func includes(_ tool: AgentTool) -> Bool {
        switch tool {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI:
            true
        case .codex, .geminiCLI, .openCode, .cursor:
            false
        }
    }

    /// Claude-family sessions from a state snapshot, preserving the engine's
    /// own ordering (`SessionState.sessions`).
    public static func claudeSessions(in state: SessionState) -> [AgentSession] {
        state.sessions.filter { includes($0.tool) }
    }
}
