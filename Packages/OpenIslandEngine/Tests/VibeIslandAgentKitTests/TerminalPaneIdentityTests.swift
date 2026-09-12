import Foundation
import Testing
@testable import OpenIslandCore

// MARK: - Fixtures

/// The agent runs in the pane on ttys003; the user is looking at ttys001.
private let ownSessionID = "A20F907A-8735-49D2-9393-D0C5EFF7CB38"
private let ownTTY = "/dev/ttys003"
private let focusedSessionID = "D1DBA19A-4743-4949-82F1-E8E80E9155F7"
private let focusedTTY = "/dev/ttys001"

private let iTermEnvironment = [
    "TERM_PROGRAM": "iTerm.app",
    "ITERM_SESSION_ID": "w0t4p0:\(ownSessionID)",
]

/// Records whether the AppleScript locator ran and answers as if the user
/// were focused on some other pane.
private final class FocusedLocatorStub: @unchecked Sendable {
    private(set) var calls = 0
    let result: (sessionID: String?, tty: String?, title: String?)

    init(sessionID: String? = focusedSessionID, tty: String? = focusedTTY, title: String? = "other tab") {
        result = (sessionID, tty, title)
    }

    func locate(_: String) -> (sessionID: String?, tty: String?, title: String?) {
        calls += 1
        return result
    }
}

// MARK: - TerminalPaneIdentity

@Suite("TerminalPaneIdentity")
struct TerminalPaneIdentityTests {
    @Test("extracts the session UUID from ITERM_SESSION_ID")
    func extractsITermSessionUUID() {
        #expect(TerminalPaneIdentity.iTermSessionID(from: iTermEnvironment) == ownSessionID)
    }

    @Test("accepts a bare UUID without the wNtNpN prefix")
    func acceptsBareUUID() {
        #expect(TerminalPaneIdentity.iTermSessionID(from: ["ITERM_SESSION_ID": ownSessionID]) == ownSessionID)
    }

    @Test("ignores a missing or blank ITERM_SESSION_ID")
    func ignoresMissingSessionID() {
        #expect(TerminalPaneIdentity.iTermSessionID(from: [:]) == nil)
        #expect(TerminalPaneIdentity.iTermSessionID(from: ["ITERM_SESSION_ID": "  "]) == nil)
    }

    @Test("ignores ITERM_SESSION_ID inside tmux, where it names the server's launch pane")
    func ignoresSessionIDInsideTmux() {
        var environment = iTermEnvironment
        environment["TMUX"] = "/private/tmp/tmux-501/default,123,0"
        #expect(TerminalPaneIdentity.iTermSessionID(from: environment) == nil)
    }

    @Test("rejects a locator describing a pane on another TTY")
    func rejectsForeignLocator() {
        #expect(!TerminalPaneIdentity.locatorDescribesOwnPane(
            locatorTTY: focusedTTY, ownTTY: ownTTY, environment: [:]
        ))
    }

    @Test("treats /dev/ttysNNN and ttysNNN as the same device")
    func normalizesDevicePrefix() {
        #expect(TerminalPaneIdentity.locatorDescribesOwnPane(
            locatorTTY: ownTTY, ownTTY: "ttys003", environment: [:]
        ))
    }

    @Test("trusts the locator when either TTY is unknown or the agent is in tmux")
    func trustsUnverifiableLocator() {
        #expect(TerminalPaneIdentity.locatorDescribesOwnPane(locatorTTY: nil, ownTTY: ownTTY, environment: [:]))
        #expect(TerminalPaneIdentity.locatorDescribesOwnPane(locatorTTY: focusedTTY, ownTTY: nil, environment: [:]))
        #expect(TerminalPaneIdentity.locatorDescribesOwnPane(
            locatorTTY: focusedTTY, ownTTY: "/dev/ttys050", environment: ["TMUX": "x"]
        ))
    }
}

// MARK: - Hook payloads

@Suite("Hook payload terminal identity")
struct HookPayloadTerminalIdentityTests {
    @Test("Claude: iTerm pane comes from the environment, not the focused session")
    func claudeUsesITermEnvironment() {
        let locator = FocusedLocatorStub()
        let payload = ClaudeHookPayload(cwd: "/tmp", hookEventName: .preToolUse, sessionID: "s")
            .withRuntimeContext(
                environment: iTermEnvironment,
                currentTTYProvider: { ownTTY },
                terminalLocatorProvider: locator.locate
            )

        #expect(payload.terminalApp == "iTerm")
        #expect(payload.terminalSessionID == ownSessionID)
        #expect(payload.terminalTTY == ownTTY)
        #expect(payload.terminalTitle == nil)
        #expect(locator.calls == 0)
    }

    @Test("Claude: without ITERM_SESSION_ID, a locator on another TTY is discarded")
    func claudeDiscardsForeignLocator() {
        let locator = FocusedLocatorStub()
        let payload = ClaudeHookPayload(cwd: "/tmp", hookEventName: .preToolUse, sessionID: "s")
            .withRuntimeContext(
                environment: ["TERM_PROGRAM": "iTerm.app"],
                currentTTYProvider: { ownTTY },
                terminalLocatorProvider: locator.locate
            )

        #expect(locator.calls == 1)
        #expect(payload.terminalSessionID == nil)
        #expect(payload.terminalTTY == ownTTY)
        #expect(payload.terminalTitle == nil)
    }

    @Test("Claude: a Terminal.app locator on the agent's own TTY is still used")
    func claudeKeepsMatchingLocator() {
        let locator = FocusedLocatorStub(sessionID: nil, tty: ownTTY, title: "build")
        let payload = ClaudeHookPayload(cwd: "/tmp", hookEventName: .preToolUse, sessionID: "s")
            .withRuntimeContext(
                environment: ["TERM_PROGRAM": "Apple_Terminal"],
                currentTTYProvider: { ownTTY },
                terminalLocatorProvider: locator.locate
            )

        #expect(payload.terminalApp == "Terminal")
        #expect(payload.terminalTTY == ownTTY)
        #expect(payload.terminalTitle == "build")
    }

    @Test("Codex: iTerm pane comes from the environment, not the focused session")
    func codexUsesITermEnvironment() {
        let locator = FocusedLocatorStub()
        let payload = CodexHookPayload(
            cwd: "/tmp",
            hookEventName: .preToolUse,
            model: "gpt",
            permissionMode: .default,
            sessionID: "s",
            transcriptPath: nil
        )
        .withRuntimeContext(
            environment: iTermEnvironment,
            currentTTYProvider: { ownTTY },
            terminalLocatorProvider: locator.locate
        )

        #expect(payload.terminalSessionID == ownSessionID)
        #expect(payload.terminalTTY == ownTTY)
        #expect(locator.calls == 0)
    }

    @Test("Codex: without ITERM_SESSION_ID, a locator on another TTY is discarded")
    func codexDiscardsForeignLocator() {
        let locator = FocusedLocatorStub()
        let payload = CodexHookPayload(
            cwd: "/tmp",
            hookEventName: .preToolUse,
            model: "gpt",
            permissionMode: .default,
            sessionID: "s",
            transcriptPath: nil
        )
        .withRuntimeContext(
            environment: ["TERM_PROGRAM": "iTerm.app"],
            currentTTYProvider: { ownTTY },
            terminalLocatorProvider: locator.locate
        )

        #expect(payload.terminalSessionID == nil)
        #expect(payload.terminalTitle == nil)
    }

    @Test("Gemini: iTerm pane comes from the environment, not the focused session")
    func geminiUsesITermEnvironment() {
        let locator = FocusedLocatorStub()
        let payload = GeminiHookPayload(cwd: "/tmp", hookEventName: .afterAgent, sessionID: "s")
            .withRuntimeContext(
                environment: iTermEnvironment,
                currentTTYProvider: { ownTTY },
                terminalLocatorProvider: locator.locate
            )

        #expect(payload.terminalSessionID == ownSessionID)
        #expect(payload.terminalTTY == ownTTY)
        #expect(locator.calls == 0)
    }
}
