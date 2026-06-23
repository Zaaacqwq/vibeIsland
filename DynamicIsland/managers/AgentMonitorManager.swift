/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * Agent monitoring feature ported from Open Vibe Island (Open Island),
 * GPL v3 — Copyright (C) Octane0411 and Open Island contributors.
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 */

import AppKit
import AVFoundation
import Combine
import Defaults
import Foundation
import OpenIslandCore
import VibeIslandAgentKit

extension Notification.Name {
    /// Posted when a Claude session finishes a turn. `AppDelegate` listens and,
    /// if enabled, expands the notch to the Agents tab. `object` is the session ID.
    static let vibeIslandAgentDidComplete = Notification.Name("vibeIslandAgentDidComplete")
}

/// Bridges Open Island's agent-monitoring engine into Atoll's Combine /
/// `ObservableObject` world.
///
/// Owns the namespaced `BridgeServer`, consumes its observer event stream,
/// reduces events through `SessionState`, and republishes the Claude-family
/// sessions for Atoll's notch UI. Mirrors the engine's reference lifecycle
/// (`OpenIslandApp.AppModel`) but stays intentionally thin — no SwiftUI here.
@MainActor
final class AgentMonitorManager: ObservableObject {
    static let shared = AgentMonitorManager()

    enum HookStatus: Equatable {
        case unknown
        case installed
        case notInstalled
    }

    /// Aggregate status used to drive the closed-pill live activity.
    enum ClosedActivity: Equatable {
        case idle
        case running(count: Int)
        case attention(count: Int)
    }

    /// Claude-family sessions, ordered by the engine's own sort.
    @Published private(set) var sessions: [AgentSession] = [] {
        didSet { AgentInputHotkeyMonitor.shared.updatePendingState() }
    }
    /// Set by the hotkey monitor when ⌘<n> lands on a freeform ("Other") option,
    /// so the overlay can switch into text-entry mode (which needs view state).
    @Published var requestedFreeformOptionID: UUID?
    @Published private(set) var isBridgeReady = false
    @Published private(set) var hookStatus: HookStatus = .unknown
    @Published private(set) var codexHookStatus: HookStatus = .unknown
    @Published private(set) var geminiHookStatus: HookStatus = .unknown
    @Published private(set) var antigravityHookStatus: HookStatus = .unknown
    @Published private(set) var openCodeHookStatus: HookStatus = .unknown
    @Published private(set) var lastErrorMessage: String?

    /// Claude rate-limit usage (5-hour / 7-day windows), populated once the
    /// status line is installed. `nil` until the status line writes its cache.
    @Published private(set) var usage: ClaudeUsageSnapshot?
    @Published private(set) var statusLineInstalled = false

    /// The single session currently demanding attention (permission/answer),
    /// if any — drives the closed-pill live activity.
    var attentionSession: AgentSession? {
        sessions.first { $0.phase.requiresAttention }
    }

    var runningCount: Int { sessions.filter { $0.phase == .running }.count }
    var attentionCount: Int { sessions.filter { $0.phase.requiresAttention }.count }

    /// Whether the closed-pill live activity should be shown at all.
    var hasClosedActivity: Bool { closedActivity != .idle }

    /// Collapsed status for the closed pill — attention always wins over running.
    var closedActivity: ClosedActivity {
        let attention = attentionCount
        if attention > 0 { return .attention(count: attention) }
        let running = runningCount
        if running > 0 { return .running(count: running) }
        return .idle
    }

    private let configuration = VibeIslandAgentConfiguration()
    private let bridgeServer: BridgeServer
    private var bridgeClient: LocalBridgeClient?
    private var bridgeTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var state = SessionState()
    private var hasStarted = false
    private var livenessTimer: Timer?
    /// Lightweight in-memory watchdog (no `ps`) that completes idle Antigravity
    /// turns promptly, since agy never delivers its `Stop` hook.
    private var antigravityWatchdogTimer: Timer?
    /// Per-session fine-grained activity, refining the engine's coarse phase
    /// into Claude Halo's thinking / executing / compacting / idle states.
    private var haloActivity: [String: HaloState] = [:]

    private static let reconnectDelay: Duration = .seconds(2)
    private static let maxReconnectDelay: Duration = .seconds(30)
    private static let livenessPollInterval: TimeInterval = 4

    private init() {
        bridgeServer = BridgeServer(socketURL: configuration.socketURL)
    }

    // MARK: - Lifecycle

    /// Idempotently starts the bridge server and observer. Safe to call from
    /// app launch; does nothing on subsequent calls.
    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            try bridgeServer.start()
        } catch {
            lastErrorMessage = "Failed to start agent bridge: \(error.localizedDescription)"
            hasStarted = false
            return
        }

        connectObserver()
        refreshHookStatus()
        startLivenessMonitor()
        AgentInputHotkeyMonitor.shared.start()
    }

    func stop() {
        bridgeTask?.cancel()
        reconnectTask?.cancel()
        bridgeClient?.disconnect()
        bridgeServer.stop()
        livenessTimer?.invalidate()
        livenessTimer = nil
        antigravityWatchdogTimer?.invalidate()
        antigravityWatchdogTimer = nil
        isBridgeReady = false
        hasStarted = false
        AgentInputHotkeyMonitor.shared.stop()
    }

    private func connectObserver() {
        bridgeTask?.cancel()
        bridgeClient?.disconnect()

        let client = LocalBridgeClient(socketURL: configuration.socketURL)
        bridgeClient = client

        let stream: AsyncThrowingStream<AgentEvent, Error>
        do {
            stream = try client.connect()
        } catch {
            lastErrorMessage = "Failed to connect agent observer: \(error.localizedDescription)"
            scheduleReconnect()
            return
        }

        bridgeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await client.send(.registerClient(role: .observer))
                self.isBridgeReady = true
                self.lastErrorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.isBridgeReady = false
                self.scheduleReconnect()
                return
            }

            do {
                for try await event in stream {
                    self.apply(event)
                }
            } catch {}

            guard !Task.isCancelled else { return }
            self.isBridgeReady = false
            self.scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var delay = Self.reconnectDelay
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.connectObserver()
                if self.isBridgeReady { return }
                delay = min(delay * 2, Self.maxReconnectDelay)
            }
        }
    }

    // MARK: - Event reduction

    private func apply(_ event: AgentEvent) {
        trackHaloActivity(event)
        state.apply(event)
        bridgeServer.updateStateSnapshot(state)
        sessions = ClaudeSessionFilter.claudeSessions(in: state)
    }

    // MARK: - Halo state

    /// Refines a session's activity from raw events. Phase-driven states
    /// (inputNeeded / completed) are resolved in `haloState(for:)`; this only
    /// tracks the "running" sub-states the coarse phase can't express.
    private func trackHaloActivity(_ event: AgentEvent) {
        switch event {
        case let .sessionStarted(started):
            haloActivity[started.sessionID] = .idle
        case let .activityUpdated(activity):
            let summary = activity.summary
            if summary.hasPrefix("Prompt:") {
                haloActivity[activity.sessionID] = .thinking
            } else if summary.range(of: "compacting", options: .caseInsensitive) != nil {
                haloActivity[activity.sessionID] = .compacting
            } else {
                haloActivity[activity.sessionID] = .executing
            }
        case let .permissionRequested(request):
            let wasInputNeeded = haloActivity[request.sessionID] == .inputNeeded
            haloActivity[request.sessionID] = .inputNeeded
            if !wasInputNeeded { playInputNeededSoundIfEnabled() }
        case let .questionAsked(question):
            let wasInputNeeded = haloActivity[question.sessionID] == .inputNeeded
            haloActivity[question.sessionID] = .inputNeeded
            if !wasInputNeeded { playInputNeededSoundIfEnabled() }
        case let .sessionCompleted(completed):
            let wasCompleted = haloActivity[completed.sessionID] == .completed
            haloActivity[completed.sessionID] = .completed
            // Only chime / auto-expand on a turn-level completion (Stop). A full
            // session teardown (SessionEnd — e.g. closing the Claude terminal)
            // shouldn't play the completion sound or surface the notch.
            if !wasCompleted, completed.isSessionEnd != true {
                playCompletionSoundIfEnabled()
                announceCompletionIfEnabled(sessionID: completed.sessionID)
            }
        default:
            break
        }
    }

    /// Throttle so a multi-turn burst doesn't repeatedly fling the notch open.
    private var lastAutoExpandAt: Date = .distantPast
    private static let autoExpandThrottle: TimeInterval = 8

    private func announceCompletionIfEnabled(sessionID: String) {
        guard Defaults[.agentExpandOnComplete] else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAutoExpandAt) > Self.autoExpandThrottle else { return }
        lastAutoExpandAt = now
        NotificationCenter.default.post(name: .vibeIslandAgentDidComplete, object: sessionID)
    }

    // MARK: - Completion sound

    private var completionSoundPlayer: AVAudioPlayer?

    /// Plays a ding when Claude finishes a turn. Lazily loads the bundled
    /// sound and reuses the player across plays.
    private func playCompletionSoundIfEnabled() {
        guard Defaults[.agentCompletionSoundEnabled] else { return }
        if completionSoundPlayer == nil {
            guard let url = Bundle.main.url(forResource: "agent-complete", withExtension: "mp3") else { return }
            completionSoundPlayer = try? AVAudioPlayer(contentsOf: url)
            completionSoundPlayer?.prepareToPlay()
        }
        completionSoundPlayer?.currentTime = 0
        completionSoundPlayer?.play()
    }

    // MARK: - Input-needed sound

    private var inputSoundPlayer: AVAudioPlayer?
    private var lastInputSoundAt: Date = .distantPast

    /// Plays a notification when Claude needs the user to respond (permission or
    /// question — the red "input needed" halo). Throttled so a burst of events
    /// for the same prompt doesn't stack plays.
    private func playInputNeededSoundIfEnabled() {
        guard Defaults[.agentInputSoundEnabled] else { return }
        let now = Date()
        guard now.timeIntervalSince(lastInputSoundAt) > 0.5 else { return }
        lastInputSoundAt = now

        if inputSoundPlayer == nil {
            guard let url = Bundle.main.url(forResource: "agent-input-needed", withExtension: "mp3") else { return }
            inputSoundPlayer = try? AVAudioPlayer(contentsOf: url)
            inputSoundPlayer?.prepareToPlay()
        }
        inputSoundPlayer?.currentTime = 0
        inputSoundPlayer?.play()
    }

    /// The halo state for a session: phase is authoritative for attention and
    /// completion; otherwise the tracked fine-grained activity is used.
    func haloState(for session: AgentSession) -> HaloState {
        if session.phase.requiresAttention { return .inputNeeded }
        if let activity = haloActivity[session.id] {
            // Don't let a stale "completed" activity mask a session the phase
            // still considers running.
            if session.phase == .completed { return .completed }
            return activity
        }
        return session.phase == .completed ? .completed : .thinking
    }

    /// Collapsed halo for the closed pill — highest-priority state across all
    /// visible sessions.
    var aggregateHaloState: HaloState? {
        sessions.map { haloState(for: $0) }
            .max { $0.aggregatePriority < $1.aggregatePriority }
    }

    /// The session currently awaiting a permission decision or a question
    /// answer — drives the focused approve/ask overlay. Permission requests take
    /// priority over questions.
    var pendingInputSession: AgentSession? {
        sessions.first { $0.permissionRequest != nil }
            ?? sessions.first { $0.questionPrompt != nil }
    }

    // MARK: - Process liveness

    /// Closing a terminal kills Claude before it can fire its `SessionEnd`
    /// hook, so the session would otherwise linger forever. This poller checks
    /// whether each session's terminal (by TTY) still hosts a live `claude`
    /// process; sessions whose TTY no longer runs Claude are marked ended (after
    /// two consecutive misses, per `markProcessLiveness`) and pruned.
    private func startLivenessMonitor() {
        livenessTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.livenessPollInterval, repeats: true) { [weak self] _ in
            self?.reconcileProcessLiveness()
        }
        livenessTimer = timer
        reconcileProcessLiveness()

        antigravityWatchdogTimer?.invalidate()
        let watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.completeStaleAntigravitySessions()
        }
        antigravityWatchdogTimer = watchdog
    }

    private func reconcileProcessLiveness() {
        Task.detached(priority: .utility) {
            let aliveTTYs = Self.ttysHostingAgents()
            let usage = try? ClaudeUsageLoader.load()
            await MainActor.run {
                self.applyLiveness(aliveTTYs: aliveTTYs)
                if let usage { self.usage = usage }
            }
        }
    }

    /// Antigravity (`agy`) fires its `Stop` hook unreliably — it often logs the
    /// hook then tears the turn down, killing the subprocess before it reaches
    /// the bridge, so a session can stick on "Executing" forever. As a safety
    /// net, auto-complete an antigravity session that has been `running` with no
    /// new activity for this long (its short turns emit events ~1s apart, so a
    /// few seconds of quiet means the turn is done — agy never delivers `Stop`).
    private static let antigravityIdleCompleteSeconds: TimeInterval = 3

    private func completeStaleAntigravitySessions() {
        let now = Date()
        for session in state.sessions
        where session.tool == .antigravity
            && session.phase == .running
            && !session.isDemoSession
            && now.timeIntervalSince(session.updatedAt) > Self.antigravityIdleCompleteSeconds {
            apply(.sessionCompleted(
                SessionCompleted(sessionID: session.id, summary: session.summary, timestamp: now)
            ))
        }
    }

    private func applyLiveness(aliveTTYs: Set<String>) {
        completeStaleAntigravitySessions()

        // A session is "alive" if its TTY still runs Claude. Sessions with no
        // known TTY are kept alive to avoid false removal.
        let aliveIDs = Set(state.sessions.compactMap { session -> String? in
            guard let tty = session.jumpTarget?.terminalTTY, !tty.isEmpty else {
                return session.id
            }
            return aliveTTYs.contains(Self.normalizeTTY(tty)) ? session.id : nil
        })

        let changed = state.markProcessLiveness(aliveSessionIDs: aliveIDs)
        let removed = state.removeInvisibleSessions()
        guard !changed.isEmpty || removed else { return }

        if removed {
            let liveIDs = Set(state.sessions.map(\.id))
            haloActivity = haloActivity.filter { liveIDs.contains($0.key) }
        }

        bridgeServer.updateStateSnapshot(state)
        sessions = ClaudeSessionFilter.claudeSessions(in: state)
    }

    /// Process names of the agent CLIs we surface, used for TTY liveness.
    private nonisolated static let agentProcessNames = ["claude", "codex", "gemini", "agy", "opencode"]

    /// TTYs (normalized, e.g. `ttys003`) that currently host a supported agent
    /// CLI process (claude / codex / gemini). Used so a completed session whose
    /// terminal is still open isn't pruned by liveness polling — without codex/
    /// gemini here, their sessions vanished the moment the turn finished.
    private nonisolated static func ttysHostingAgents() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "tty=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var ttys: Set<String> = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " ") else { continue }
            let tty = String(line[..<space])
            let command = String(line[line.index(after: space)...])
            guard tty != "??", !tty.isEmpty else { continue }
            if agentProcessNames.contains(where: {
                command.range(of: $0, options: .caseInsensitive) != nil
            }) {
                ttys.insert(normalizeTTY(tty))
            }
        }
        return ttys
    }

    private nonisolated static func normalizeTTY(_ tty: String) -> String {
        tty.hasPrefix("/dev/") ? String(tty.dropFirst("/dev/".count)) : tty
    }

    // MARK: - Permission resolution

    /// Approve or deny the pending permission request for a session, relaying
    /// the decision back to the (blocked) hooks process via the bridge.
    func resolvePermission(sessionID: String, approved: Bool) {
        guard let session = state.session(id: sessionID),
              session.permissionRequest != nil else { return }

        let resolution: PermissionResolution = approved
            ? .allowOnce()
            : .deny(message: "Permission denied in VibeIsland.", interrupt: false)

        state.resolvePermission(sessionID: sessionID, resolution: resolution)
        bridgeServer.updateStateSnapshot(state)
        sessions = ClaudeSessionFilter.claudeSessions(in: state)

        send(.resolvePermission(sessionID: sessionID, resolution: resolution))
    }

    /// Answer the pending question for a session, relaying the choice back to
    /// the (blocked) hooks process via the bridge.
    func answerQuestion(sessionID: String, response: QuestionPromptResponse) {
        guard let session = state.session(id: sessionID),
              session.questionPrompt != nil else { return }

        state.answerQuestion(sessionID: sessionID, response: response)
        bridgeServer.updateStateSnapshot(state)
        sessions = ClaudeSessionFilter.claudeSessions(in: state)

        send(.answerQuestion(sessionID: sessionID, response: response))
    }

    /// Convenience: answer a single-question prompt by the chosen option label.
    func answerQuestion(sessionID: String, optionLabel: String) {
        answerQuestion(sessionID: sessionID, response: QuestionPromptResponse(answer: optionLabel))
    }

    private func send(_ command: BridgeCommand) {
        guard let client = bridgeClient else { return }
        Task {
            do {
                try await client.send(command)
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Failed to send agent decision: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Jump-back

    private let jumpService = TerminalJumpService()

    /// Focus the terminal window/tab/pane that owns the agent session, using
    /// the vendored Open Island jump service (AppleScript + TTY/tmux targeting
    /// for Terminal.app, iTerm, Ghostty, Warp, WezTerm, VS Code, JetBrains, …).
    func jumpBack(to session: AgentSession) {
        guard let target = session.jumpTarget else {
            lastErrorMessage = "No terminal location is known for this session yet."
            return
        }
        do {
            _ = try jumpService.jump(to: target)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Couldn't jump to the terminal: \(error.localizedDescription)"
        }
    }

    /// Finds the session's transcript (`~/.claude/projects/<proj>/<id>.jsonl`)
    /// and reads the `cwd` it recorded — the directory the session was launched
    /// in, which `claude --resume` needs.
    private nonisolated static func resolveSessionLaunchDirectory(sessionID: String) -> String? {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: nil
        ) else { return nil }

        for dir in dirs {
            let transcript = dir.appendingPathComponent("\(sessionID).jsonl")
            guard FileManager.default.fileExists(atPath: transcript.path) else { continue }
            if let cwd = cwdFromTranscript(transcript) { return cwd }
        }
        return nil
    }

    /// Scans the start of a transcript for the first record carrying a `cwd`
    /// (the leading `mode` / `permission-mode` / snapshot records don't have
    /// one — it first appears on `user` entries).
    private nonisolated static func cwdFromTranscript(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let cwd = object["cwd"] as? String, !cwd.isEmpty
            else { continue }
            return cwd
        }
        return nil
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Hook installation

    /// Location of the hooks CLI bundled inside `Atoll.app/Contents/Helpers`.
    var bundledHooksBinaryURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/OpenIslandHooks")
    }

    func refreshHookStatus() {
        let installer = VibeIslandClaudeHookInstaller(configuration: configuration)
        Task.detached {
            let status: HookStatus
            do {
                let result = try installer.status()
                status = result.managedHooksPresent ? .installed : .notInstalled
            } catch {
                status = .unknown
            }
            await MainActor.run { self.hookStatus = status }
        }
    }

    func installHooks() {
        let installer = VibeIslandClaudeHookInstaller(configuration: configuration)
        let binaryURL = bundledHooksBinaryURL
        Task.detached {
            var message: String?
            var status: HookStatus = .unknown
            do {
                let result = try installer.install(bundledBinaryURL: binaryURL)
                status = result.managedHooksPresent ? .installed : .notInstalled
            } catch {
                message = "Failed to install Claude hooks: \(error.localizedDescription)"
            }
            await MainActor.run {
                self.hookStatus = status
                if let message { self.lastErrorMessage = message }
            }
        }
    }

    func uninstallHooks() {
        let installer = VibeIslandClaudeHookInstaller(configuration: configuration)
        Task.detached {
            var message: String?
            do {
                _ = try installer.uninstall()
            } catch {
                message = "Failed to remove Claude hooks: \(error.localizedDescription)"
            }
            await MainActor.run {
                self.hookStatus = .notInstalled
                if let message { self.lastErrorMessage = message }
            }
        }
    }

    // MARK: - Codex / Gemini hooks (reuse the bundled OpenIslandHooks binary)

    /// Shared plumbing for the Codex/Gemini install/uninstall/status calls:
    /// runs `work` off the main actor, maps thrown errors to `lastErrorMessage`,
    /// and publishes the resulting `HookStatus` via `assign`.
    private func applyHookChange(
        label: String,
        assign: @escaping @MainActor @Sendable (HookStatus) -> Void,
        work: @escaping @Sendable () throws -> Bool
    ) {
        Task.detached {
            var message: String?
            var status: HookStatus = .unknown
            do {
                status = try work() ? .installed : .notInstalled
            } catch {
                message = "Failed to \(label): \(error.localizedDescription)"
            }
            await MainActor.run {
                assign(status)
                if let message { self.lastErrorMessage = message }
            }
        }
    }

    func refreshCodexHookStatus() {
        applyHookChange(label: "check Codex hooks", assign: { self.codexHookStatus = $0 }) {
            try CodexHookInstallationManager().status().managedHooksPresent
        }
    }

    func installCodexHooks() {
        let binary = bundledHooksBinaryURL
        applyHookChange(label: "install Codex hooks", assign: { self.codexHookStatus = $0 }) {
            try CodexHookInstallationManager().install(hooksBinaryURL: binary).managedHooksPresent
        }
    }

    func uninstallCodexHooks() {
        applyHookChange(label: "remove Codex hooks", assign: { self.codexHookStatus = $0 }) {
            _ = try CodexHookInstallationManager().uninstall()
            return false
        }
    }

    func refreshGeminiHookStatus() {
        applyHookChange(label: "check Gemini hooks", assign: { self.geminiHookStatus = $0 }) {
            try GeminiHookInstallationManager().status().managedHooksPresent
        }
    }

    func installGeminiHooks() {
        let binary = bundledHooksBinaryURL
        applyHookChange(label: "install Gemini hooks", assign: { self.geminiHookStatus = $0 }) {
            try GeminiHookInstallationManager().install(hooksBinaryURL: binary).managedHooksPresent
        }
    }

    func uninstallGeminiHooks() {
        applyHookChange(label: "remove Gemini hooks", assign: { self.geminiHookStatus = $0 }) {
            _ = try GeminiHookInstallationManager().uninstall()
            return false
        }
    }

    func refreshAntigravityHookStatus() {
        applyHookChange(label: "check Antigravity hooks", assign: { self.antigravityHookStatus = $0 }) {
            try AntigravityHookInstallationManager().status().managedHooksPresent
        }
    }

    func installAntigravityHooks() {
        let binary = bundledHooksBinaryURL
        applyHookChange(label: "install Antigravity hooks", assign: { self.antigravityHookStatus = $0 }) {
            try AntigravityHookInstallationManager().install(hooksBinaryURL: binary).managedHooksPresent
        }
    }

    func uninstallAntigravityHooks() {
        applyHookChange(label: "remove Antigravity hooks", assign: { self.antigravityHookStatus = $0 }) {
            _ = try AntigravityHookInstallationManager().uninstall()
            return false
        }
    }

    // MARK: - OpenCode plugin installation

    /// OpenCode loads a JS plugin (not the hooks CLI binary). The bundled plugin
    /// defaults to the legacy OpenIsland socket, so patch it to VibeIsland's
    /// before installing.
    private func openCodePluginSource() throws -> Data {
        guard let url = Bundle.main.url(forResource: "open-island-opencode", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            throw NSError(
                domain: "VibeIsland.OpenCode", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled OpenCode plugin (open-island-opencode.js) is missing."]
            )
        }
        let patched = js.replacingOccurrences(
            of: "Library/Application Support/OpenIsland/bridge.sock",
            with: "Library/Application Support/VibeIsland/agent-bridge.sock"
        )
        return Data(patched.utf8)
    }

    func refreshOpenCodeHookStatus() {
        applyHookChange(label: "check OpenCode plugin", assign: { self.openCodeHookStatus = $0 }) {
            try OpenCodePluginInstallationManager().status().isInstalled
        }
    }

    func installOpenCodeHooks() {
        let source: Data
        do { source = try openCodePluginSource() } catch {
            lastErrorMessage = error.localizedDescription
            return
        }
        applyHookChange(label: "install OpenCode plugin", assign: { self.openCodeHookStatus = $0 }) {
            try OpenCodePluginInstallationManager().install(pluginSourceData: source).isInstalled
        }
    }

    func uninstallOpenCodeHooks() {
        applyHookChange(label: "remove OpenCode plugin", assign: { self.openCodeHookStatus = $0 }) {
            _ = try OpenCodePluginInstallationManager().uninstall()
            return false
        }
    }

    // MARK: - Usage status line
    //
    // Claude rate-limit usage is produced by a managed status line script that
    // Claude Code runs on each render; it writes the 5h/7d windows to a cache
    // that `ClaudeUsageLoader` reads. Installing it modifies the `statusLine`
    // entry in ~/.claude/settings.json (separate from the hooks).

    func refreshStatusLineStatus() {
        Task.detached {
            let installed = (try? ClaudeStatusLineInstallationManager().status())?
                .managedStatusLineInstalled ?? false
            await MainActor.run { self.statusLineInstalled = installed }
        }
    }

    func installStatusLine() {
        Task.detached {
            var message: String?
            var installed = false
            do {
                installed = try ClaudeStatusLineInstallationManager().install().managedStatusLineInstalled
            } catch {
                message = "Couldn't install the usage status line: \(error.localizedDescription)"
            }
            await MainActor.run {
                self.statusLineInstalled = installed
                if let message { self.lastErrorMessage = message }
            }
        }
    }

    func uninstallStatusLine() {
        Task.detached {
            var message: String?
            do {
                _ = try ClaudeStatusLineInstallationManager().uninstall()
            } catch {
                message = "Couldn't remove the usage status line: \(error.localizedDescription)"
            }
            await MainActor.run {
                self.statusLineInstalled = false
                self.usage = nil
                if let message { self.lastErrorMessage = message }
            }
        }
    }
}
