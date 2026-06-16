/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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
import Combine
import Foundation
import OpenIslandCore
import AtollAgentKit

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
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var isBridgeReady = false
    @Published private(set) var hookStatus: HookStatus = .unknown
    @Published private(set) var lastErrorMessage: String?

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

    private let configuration = AtollAgentConfiguration()
    private let bridgeServer: BridgeServer
    private var bridgeClient: LocalBridgeClient?
    private var bridgeTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var state = SessionState()
    private var hasStarted = false

    private static let reconnectDelay: Duration = .seconds(2)
    private static let maxReconnectDelay: Duration = .seconds(30)

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
    }

    func stop() {
        bridgeTask?.cancel()
        reconnectTask?.cancel()
        bridgeClient?.disconnect()
        bridgeServer.stop()
        isBridgeReady = false
        hasStarted = false
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
        state.apply(event)
        bridgeServer.updateStateSnapshot(state)
        sessions = ClaudeSessionFilter.claudeSessions(in: state)
    }

    // MARK: - Permission resolution

    /// Approve or deny the pending permission request for a session, relaying
    /// the decision back to the (blocked) hooks process via the bridge.
    func resolvePermission(sessionID: String, approved: Bool) {
        guard let session = state.session(id: sessionID),
              session.permissionRequest != nil else { return }

        let resolution: PermissionResolution = approved
            ? .allowOnce()
            : .deny(message: "Permission denied in Atoll.", interrupt: false)

        state.resolvePermission(sessionID: sessionID, resolution: resolution)
        bridgeServer.updateStateSnapshot(state)
        sessions = ClaudeSessionFilter.claudeSessions(in: state)

        send(.resolvePermission(sessionID: sessionID, resolution: resolution))
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

    // MARK: - Jump-back (minimal: activate the originating terminal app)

    func jumpBack(to session: AgentSession) {
        guard let target = session.jumpTarget else { return }
        let appName = target.terminalApp
        let workspace = NSWorkspace.shared
        // Match a running app by localized name (e.g. "Ghostty", "Terminal").
        let trimmed = appName.replacingOccurrences(of: ".app", with: "")
        if let running = workspace.runningApplications.first(where: {
            ($0.localizedName ?? "").caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            running.activate(options: [.activateAllWindows])
            return
        }
        // Fall back to launching the app by name if it isn't running.
        if let url = workspace.urlForApplication(withBundleIdentifier: appName)
            ?? NSWorkspace.shared.fullPath(forApplication: trimmed).map(URL.init(fileURLWithPath:)) {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Hook installation

    /// Location of the hooks CLI bundled inside `Atoll.app/Contents/Helpers`.
    var bundledHooksBinaryURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/OpenIslandHooks")
    }

    func refreshHookStatus() {
        let installer = AtollClaudeHookInstaller(configuration: configuration)
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
        let installer = AtollClaudeHookInstaller(configuration: configuration)
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
        let installer = AtollClaudeHookInstaller(configuration: configuration)
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
}
