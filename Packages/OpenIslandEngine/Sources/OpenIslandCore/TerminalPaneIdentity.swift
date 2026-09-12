import Foundation

/// Decides which terminal pane a hook invocation belongs to.
///
/// The AppleScript locators in the hook payloads (`current session of current
/// window` for iTerm, `selected tab of front window` for Terminal.app) report
/// whichever pane has *focus* when the hook runs — not the pane the agent
/// lives in. Hooks fire on every tool call, so once the user switches to
/// another tab the locator stamps that tab's identity onto the agent's
/// jump target and jump-back lands in the wrong place.
enum TerminalPaneIdentity {
    /// iTerm exports `ITERM_SESSION_ID=w0t1p0:<UUID>` into every session's
    /// shell; the UUID is what AppleScript's `id of session` returns. Unlike
    /// the focused-session locator it is fixed for the pane's lifetime.
    ///
    /// Inside tmux the variable is inherited from whichever iTerm session
    /// started the tmux server, so it says nothing about the current pane.
    static func iTermSessionID(from environment: [String: String]) -> String? {
        guard environment["TMUX"] == nil,
              let raw = environment["ITERM_SESSION_ID"]?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }

        let uuid = raw.split(separator: ":", maxSplits: 1).last.map(String.init) ?? raw
        return uuid.isEmpty ? nil : uuid
    }

    /// Whether a focused-terminal locator result describes the agent's own
    /// pane. When both TTYs are known and differ, the focused pane is some
    /// other tab and nothing the locator returned should be used.
    ///
    /// Inside tmux the agent's TTY is a tmux pty that never matches the host
    /// terminal's, so there is nothing to compare against.
    static func locatorDescribesOwnPane(
        locatorTTY: String?,
        ownTTY: String?,
        environment: [String: String]
    ) -> Bool {
        guard environment["TMUX"] == nil,
              let locatorTTY = normalizedTTY(locatorTTY),
              let ownTTY = normalizedTTY(ownTTY)
        else {
            return true
        }
        return locatorTTY == ownTTY
    }

    /// `/dev/ttys003` and `ttys003` name the same device: `tty(1)` and iTerm
    /// report the former, `ps -o tty=` the latter.
    static func normalizedTTY(_ tty: String?) -> String? {
        guard let trimmed = tty?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed.hasPrefix("/dev/") ? String(trimmed.dropFirst("/dev/".count)) : trimmed
    }
}
