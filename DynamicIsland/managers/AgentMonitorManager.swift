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

    /// Posted when an agent session needs input (permission/approve or a
    /// question). `AppDelegate` listens and expands the notch so the approve/ask
    /// overlay surfaces. `object` is the session ID.
    static let vibeIslandAgentNeedsInput = Notification.Name("vibeIslandAgentNeedsInput")
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
        didSet {
            pruneCollapsedInputSessions()
            AgentInputHotkeyMonitor.shared.updatePendingState()
            syncCodexRolloutTargets()
        }
    }

    /// Sessions whose approve/ask prompt the user collapsed — excluded from
    /// `activeInputSession` until the request resolves or the user reopens it
    /// from the agent row.
    @Published private(set) var collapsedInputSessionIDs: Set<String> = []
    /// Set by the hotkey monitor when ⌘<n> lands on a freeform ("Other") option,
    /// so the overlay can switch into text-entry mode (which needs view state).
    @Published var requestedFreeformOptionID: UUID?
    @Published private(set) var isBridgeReady = false
    @Published private(set) var hookStatus: HookStatus = .unknown
    @Published private(set) var codexHookStatus: HookStatus = .unknown
    @Published private(set) var antigravityHookStatus: HookStatus = .unknown
    @Published private(set) var openCodeHookStatus: HookStatus = .unknown
    @Published private(set) var cursorHookStatus: HookStatus = .unknown
    @Published private(set) var geminiHookStatus: HookStatus = .unknown
    @Published private(set) var lastErrorMessage: String?

    /// Claude rate-limit usage (5-hour / 7-day windows), populated once the
    /// status line is installed. `nil` until the status line writes its cache.
    @Published private(set) var usage: ClaudeUsageSnapshot?
    @Published private(set) var statusLineInstalled = false

    /// Codex rate-limit usage (primary 5h / secondary weekly windows). Unlike
    /// Claude, Codex records `rate_limits` straight into its session rollouts, so
    /// no install step is needed — we read the most recent rollout under
    /// `~/.codex/sessions`. `nil` until a rollout with rate limits is found.
    @Published private(set) var codexUsage: CodexUsageSnapshot?

    /// Rolling 14-day token usage / cost / cache summary across all agents,
    /// aggregated from local transcripts. `nil` until the first aggregation
    /// finishes; drives the Agents tab's "Token Usage" card.
    @Published private(set) var tokenUsage: TokenUsageSummary?
    /// Detailed rolling usage split by provider, used by the Agents tab's
    /// switchable provider cards while preserving the aggregate summary above.
    @Published private(set) var detailedTokenUsage: AgentUsageSummary?
    /// Provider-neutral quota windows for providers whose limits require
    /// asynchronous network or authenticated web-session loading.
    @Published private(set) var providerQuotas: [AgentUsageProviderID: ProviderQuotaSnapshot] = [:]
    /// Whether an aggregation pass is currently running (spins the card's
    /// refresh control).
    @Published private(set) var isRefreshingTokenUsage = false

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
    /// Polls each tracked Codex session's rollout JSONL for rich state the hooks
    /// don't deliver — most importantly `request_user_input` (Codex asked a
    /// question) and `usage_limit_exceeded`. Feeds its events back through
    /// `apply(_:)`. Targets are kept in sync with the live Codex sessions.
    private let codexRolloutWatcher = CodexRolloutWatcher()
    private var lastCodexRolloutTargets: [CodexRolloutWatchTarget] = []
    private let tokenUsageProvider = AgentTokenUsageProvider()
    private let providerQuotaStore = ProviderQuotaStore(fetchers: [
        AntigravityQuotaFetcher(
            credentialStore: AntigravityKeychainCredentialStore.shared
        ),
        OpenCodeWebQuotaFetcher(),
    ])
    private var lastTokenUsageRefresh: Date?
    private static let tokenUsageTTL: TimeInterval = 60
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
        refreshTokenUsage()
        AgentInputHotkeyMonitor.shared.start()

        // Feed rollout-derived Codex events (questions, usage-limit, richer
        // activity) back through the same apply path as bridge events.
        codexRolloutWatcher.eventHandler = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.apply(event)
            }
        }
    }

    /// Keeps the Codex rollout watcher pointed at exactly the live Codex
    /// sessions that expose a transcript path (the rollout JSONL). Cheap and
    /// idempotent — only re-syncs when the target set actually changes.
    private func syncCodexRolloutTargets() {
        let targets = state.sessions
            .compactMap { session -> CodexRolloutWatchTarget? in
                guard session.tool == .codex, !session.isDemoSession,
                      let path = session.codexMetadata?.transcriptPath, !path.isEmpty else {
                    return nil
                }
                return CodexRolloutWatchTarget(sessionID: session.id, transcriptPath: path)
            }
            .sorted { $0.sessionID < $1.sessionID }

        guard targets != lastCodexRolloutTargets else { return }
        lastCodexRolloutTargets = targets
        codexRolloutWatcher.sync(targets: targets)
    }

    // MARK: - Token usage

    /// Recomputes the rolling token-usage summary off the main thread. Honors a
    /// short TTL so opening the Agents tab repeatedly doesn't re-walk every
    /// transcript; pass `force: true` for the card's manual refresh button.
    ///
    /// `refreshQuotas` couples in a full provider-quota re-poll — the right
    /// behavior for the user-facing refresh button, but callers that only
    /// changed local token data (e.g. Cursor writing a fresh usage CSV) pass
    /// `false` so they don't wake every provider's quota fetcher — which would,
    /// among other things, spin up OpenCode's headless web view and flip its
    /// "Refreshing…" state.
    func refreshTokenUsage(force: Bool = false, refreshQuotas: Bool = true) {
        if refreshQuotas {
            refreshProviderQuotas(force: force)
        }

        if !force, let last = lastTokenUsageRefresh,
           Date().timeIntervalSince(last) < Self.tokenUsageTTL {
            return
        }
        guard !isRefreshingTokenUsage else { return }
        isRefreshingTokenUsage = true

        let provider = tokenUsageProvider
        Task.detached(priority: .utility) {
            let summary = provider.detailedSnapshot()
            await MainActor.run {
                self.detailedTokenUsage = summary
                self.tokenUsage = summary.total
                self.lastTokenUsageRefresh = Date()
                self.isRefreshingTokenUsage = false
            }
        }
    }

    func refreshProviderQuotas(force: Bool = false) {
        let store = providerQuotaStore
        Task {
            let snapshots = await store.snapshots(forceRefresh: force)
            self.providerQuotas = snapshots
        }
    }

    /// Refreshes a single provider's quota headlessly (used by OpenCode's
    /// background loop, turn-completion trigger, and manual Refresh button)
    /// without re-hitting every other provider.
    func refreshProviderQuota(_ providerID: AgentUsageProviderID, force: Bool = false) {
        let store = providerQuotaStore
        Task {
            if let snapshot = await store.refreshSnapshot(for: providerID, force: force) {
                self.providerQuotas[providerID] = snapshot
            }
        }
    }

    func clearProviderQuota(_ providerID: AgentUsageProviderID) {
        providerQuotas.removeValue(forKey: providerID)
        let store = providerQuotaStore
        Task {
            await store.removeSnapshot(for: providerID)
        }
    }

    func recordProviderQuota(_ snapshot: ProviderQuotaSnapshot) {
        providerQuotas[snapshot.providerID] = snapshot
        let store = providerQuotaStore
        Task {
            await store.storeSnapshot(snapshot)
        }
    }

    func stop() {
        bridgeTask?.cancel()
        reconnectTask?.cancel()
        bridgeClient?.disconnect()
        bridgeServer.stop()
        codexRolloutWatcher.stop()
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

        // Surface the notch when a session needs the user (permission/question).
        // Routed through a notification handled at the app/window level, which
        // reliably opens the notch — the SwiftUI onChange auto-open in
        // ContentView doesn't always fire.
        switch event {
        case let .permissionRequested(payload):
            postNeedsInput(sessionID: payload.sessionID)
        case let .questionAsked(payload):
            postNeedsInput(sessionID: payload.sessionID)
        case let .sessionCompleted(payload):
            if payload.isSessionEnd != true,
               state.session(id: payload.sessionID)?.tool == .openCode {
                OpenCodeQuotaSessionManager.shared.refreshAfterOpenCodeTurnCompleted()
            }
        default:
            break
        }
    }

    // MARK: - Halo state

    /// Refines a session's activity from raw events. Phase-driven states
    /// (inputNeeded / completed) are resolved in `haloState(for:)`; this only
    /// tracks the "running" sub-states the coarse phase can't express.
    private func trackHaloActivity(_ event: AgentEvent) {
        switch event {
        case let .sessionStarted(started):
            // No fine-grained activity yet — clear any stale entry (e.g. a reused
            // session id) and let `haloState(for:)` fall back to the phase
            // (completed = ready, running = thinking) until the first activity.
            haloActivity[started.sessionID] = nil
        case let .activityUpdated(activity):
            let summary = activity.summary
            if activity.phase.requiresAttention {
                // A detected (non-interactive) prompt delivered as an activity —
                // e.g. Codex asked via the `request_user_input` tool call. This is
                // a real "waiting for your answer" signal, so chime + surface
                // immediately (no debounce — unlike the Cursor timing heuristic).
                // The prompt text is in `summary`; the user answers in the terminal.
                cancelCursorWaitSound(for: activity.sessionID)
                let wasAttention = haloActivity[activity.sessionID] == .inputNeeded
                haloActivity[activity.sessionID] = .inputNeeded
                if !wasAttention {
                    playInputNeededSoundIfEnabled()
                    postNeedsInput(sessionID: activity.sessionID)
                }
                return
            }
            if activity.attentionHint == true {
                // Lightweight "waiting on the user" hint (e.g. Cursor is prompting
                // for command approval). Red halo immediately — no overlay, since
                // phase stays .running and no permissionRequest is set. The sound
                // is DEBOUNCED: Cursor gives no real-time "awaiting approval"
                // signal (the before→after gap conflates approval wait with a
                // command's own run time), so we only chime if the hint isn't
                // cleared by a matching after*Execution within a short window —
                // i.e. Cursor is genuinely blocked waiting on the user.
                haloActivity[activity.sessionID] = .inputNeeded
                scheduleCursorWaitSound(for: activity.sessionID)
            } else {
                cancelCursorWaitSound(for: activity.sessionID)
                if summary.hasPrefix("Prompt:") {
                    haloActivity[activity.sessionID] = .thinking
                } else if summary.range(of: "compacting", options: .caseInsensitive) != nil {
                    haloActivity[activity.sessionID] = .compacting
                } else {
                    haloActivity[activity.sessionID] = .executing
                }
            }
        case let .permissionRequested(request):
            cancelCursorWaitSound(for: request.sessionID)
            let wasInputNeeded = haloActivity[request.sessionID] == .inputNeeded
            haloActivity[request.sessionID] = .inputNeeded
            if !wasInputNeeded { playInputNeededSoundIfEnabled() }
        case let .questionAsked(question):
            cancelCursorWaitSound(for: question.sessionID)
            let wasInputNeeded = haloActivity[question.sessionID] == .inputNeeded
            haloActivity[question.sessionID] = .inputNeeded
            if !wasInputNeeded { playInputNeededSoundIfEnabled() }
        case let .sessionCompleted(completed):
            cancelCursorWaitSound(for: completed.sessionID)
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

    private func postNeedsInput(sessionID: String) {
        guard Defaults[.enableAgentMonitoring] else { return }
        guard Defaults[.agentExpandOnInputNeeded] else { return }
        NotificationCenter.default.post(name: .vibeIslandAgentNeedsInput, object: sessionID)
    }

    private func announceCompletionIfEnabled(sessionID: String) {
        guard Defaults[.agentExpandOnComplete] else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAutoExpandAt) > Self.autoExpandThrottle else { return }
        lastAutoExpandAt = now
        NotificationCenter.default.post(name: .vibeIslandAgentDidComplete, object: sessionID)
    }

    // MARK: - Agent sounds

    /// Resolves the sound to play for an agent event: a user-supplied file (when
    /// set and present on disk) overrides the bundled default.
    static func resolveAgentSoundURL(customPath: String, bundled: String, ext: String) -> URL? {
        if !customPath.isEmpty, FileManager.default.fileExists(atPath: customPath) {
            return URL(fileURLWithPath: customPath)
        }
        return Bundle.main.url(forResource: bundled, withExtension: ext)
    }

    // MARK: - Completion sound

    private var completionSoundPlayer: AVAudioPlayer?
    private var completionSoundURL: URL?

    /// Plays a ding when an agent finishes a turn. Reuses the cached player, but
    /// rebuilds it when the user swaps in (or clears) a custom sound file.
    private func playCompletionSoundIfEnabled() {
        guard Defaults[.agentCompletionSoundEnabled] else { return }
        guard let url = Self.resolveAgentSoundURL(customPath: Defaults[.agentCompletionSoundPath], bundled: "agent-complete", ext: "mp3") else { return }
        if completionSoundPlayer == nil || completionSoundURL != url {
            completionSoundPlayer = try? AVAudioPlayer(contentsOf: url)
            completionSoundPlayer?.prepareToPlay()
            completionSoundURL = url
        }
        completionSoundPlayer?.currentTime = 0
        completionSoundPlayer?.play()
    }

    // MARK: - Input-needed sound

    private var inputSoundPlayer: AVAudioPlayer?
    private var inputSoundURL: URL?
    private var lastInputSoundAt: Date = .distantPast

    /// Plays a notification when an agent needs the user to respond (permission or
    /// question — the red "input needed" halo). Throttled so a burst of events
    /// for the same prompt doesn't stack plays.
    private func playInputNeededSoundIfEnabled() {
        guard Defaults[.agentInputSoundEnabled] else { return }
        let now = Date()
        guard now.timeIntervalSince(lastInputSoundAt) > 0.5 else { return }
        lastInputSoundAt = now

        guard let url = Self.resolveAgentSoundURL(customPath: Defaults[.agentInputSoundPath], bundled: "agent-input-needed", ext: "mp3") else { return }
        if inputSoundPlayer == nil || inputSoundURL != url {
            inputSoundPlayer = try? AVAudioPlayer(contentsOf: url)
            inputSoundPlayer?.prepareToPlay()
            inputSoundURL = url
        }
        inputSoundPlayer?.currentTime = 0
        inputSoundPlayer?.play()
    }

    // MARK: - Cursor "awaiting approval" debounced sound

    /// Pending (not-yet-fired) wait chimes, keyed by session. A hint that clears
    /// quickly (the command ran / auto-ran) cancels its chime before it fires.
    private var pendingCursorWaitSounds: [String: DispatchWorkItem] = [:]

    /// How long a Cursor `attentionHint` must persist (no matching
    /// `after*Execution`) before we treat it as a genuine "awaiting your
    /// approval" and chime. Long enough that fast auto-run commands don't chime;
    /// short enough to alert before the user would otherwise notice.
    private static let cursorWaitSoundDelay: TimeInterval = 2.0

    private func scheduleCursorWaitSound(for sessionID: String) {
        pendingCursorWaitSounds[sessionID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCursorWaitSounds[sessionID] = nil
            // Still flagged as needing input when the timer fires → Cursor is
            // genuinely blocked waiting on the user.
            guard self.haloActivity[sessionID] == .inputNeeded else { return }
            self.playInputNeededSoundIfEnabled()
        }
        pendingCursorWaitSounds[sessionID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cursorWaitSoundDelay, execute: work)
    }

    private func cancelCursorWaitSound(for sessionID: String) {
        pendingCursorWaitSounds.removeValue(forKey: sessionID)?.cancel()
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

    private func hasPendingInput(_ session: AgentSession) -> Bool {
        session.permissionRequest != nil || session.questionPrompt != nil
    }

    /// The session whose approve/ask overlay should show inside the Agents tab —
    /// the highest-priority pending request the user hasn't collapsed. Pure
    /// derived value so it never desyncs from the tab.
    var activeInputSession: AgentSession? {
        sessions.first { $0.permissionRequest != nil && !collapsedInputSessionIDs.contains($0.id) }
            ?? sessions.first { $0.questionPrompt != nil && !collapsedInputSessionIDs.contains($0.id) }
    }

    /// Collapse the shown prompt without answering; it stays pending and can be
    /// reopened from its agent row.
    func collapseActiveInput() {
        if let id = activeInputSession?.id { collapsedInputSessionIDs.insert(id) }
    }

    /// Reopen a previously-collapsed prompt (e.g. "Respond" from its row).
    func presentInput(for sessionID: String) {
        collapsedInputSessionIDs.remove(sessionID)
    }

    private func pruneCollapsedInputSessions() {
        let stale = collapsedInputSessionIDs.filter { id in
            !(sessions.first(where: { $0.id == id }).map(hasPendingInput) ?? false)
        }
        if !stale.isEmpty { collapsedInputSessionIDs.subtract(stale) }
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
            let codexUsage = try? CodexUsageLoader.load()
            await MainActor.run {
                self.applyLiveness(aliveTTYs: aliveTTYs)
                if let usage { self.usage = usage }
                if let codexUsage { self.codexUsage = codexUsage }
            }
        }
    }

    /// Antigravity (`agy`) fires its `Stop` hook unreliably — it often logs the
    /// hook then tears the turn down, killing the subprocess before it reaches
    /// the bridge, so a session can stick on "Executing" forever. As a safety
    /// net, auto-complete an antigravity session that has been `running` with no
    /// new activity for this long.
    ///
    /// This is a heuristic: the only signal we get is "time since the last hook
    /// event", and the app never sees `PostToolUse` (the bridge suppresses it),
    /// so the clock measures time since a tool *started*. The threshold must
    /// therefore exceed the model's think time between tool calls, otherwise a
    /// normal pause after a fast tool (read/write) is misread as task-complete —
    /// which fires the completion chime and flips the card to "Completed" mid-
    /// task, then the next `PreToolUse` re-opens it (chime storm). 3s was too
    /// tight for real tasks; 10s clears typical inter-tool thinking gaps while
    /// still auto-completing within a reasonable window when `Stop` never lands.
    private static let antigravityIdleCompleteSeconds: TimeInterval = 10

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
            // Present but untrusted hooks never run (Codex 0.130+ trust gate),
            // so only report "installed" when the trust entries are in place.
            try CodexHookInstallationManager().status().managedHooksActive
        }
    }

    func installCodexHooks() {
        let binary = bundledHooksBinaryURL
        applyHookChange(label: "install Codex hooks", assign: { self.codexHookStatus = $0 }) {
            try CodexHookInstallationManager().install(hooksBinaryURL: binary).managedHooksActive
        }
    }

    func uninstallCodexHooks() {
        applyHookChange(label: "remove Codex hooks", assign: { self.codexHookStatus = $0 }) {
            _ = try CodexHookInstallationManager().uninstall()
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

    // MARK: - Cursor hooks (reuse the bundled OpenIslandHooks binary)

    func refreshCursorHookStatus() {
        applyHookChange(label: "check Cursor hooks", assign: { self.cursorHookStatus = $0 }) {
            try CursorHookInstallationManager().status().managedHooksPresent
        }
    }

    func installCursorHooks() {
        let binary = bundledHooksBinaryURL
        applyHookChange(label: "install Cursor hooks", assign: { self.cursorHookStatus = $0 }) {
            try CursorHookInstallationManager().install(hooksBinaryURL: binary).managedHooksPresent
        }
    }

    func uninstallCursorHooks() {
        applyHookChange(label: "remove Cursor hooks", assign: { self.cursorHookStatus = $0 }) {
            _ = try CursorHookInstallationManager().uninstall()
            return false
        }
    }

    // MARK: - Gemini hooks (reuse the bundled OpenIslandHooks binary)

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
