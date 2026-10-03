import Foundation
import OpenIslandCore
import Testing

@Test("Pi extension installs and removes only its managed file")
func piExtensionInstallRoundTrip() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibe-island-pi-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let manager = PiExtensionInstallationManager(agent: .pi, agentDirectory: root)
    let source = Data("const source = '__OPEN_ISLAND_PI_SOURCE__';\n".utf8)
    let sibling = manager.extensionsDirectory.appendingPathComponent("user-extension.ts")

    #expect(try !manager.status().isInstalled)
    let installed = try manager.install(extensionSourceData: source)
    #expect(installed.isCurrent)
    #expect(try String(contentsOf: manager.extensionURL, encoding: .utf8).contains("'pi'"))

    try Data("user file".utf8).write(to: sibling)
    let removed = try manager.uninstall()
    #expect(!removed.isInstalled)
    #expect(FileManager.default.fileExists(atPath: sibling.path))
}

@Test("Pi installer preserves an extension it does not own")
func piExtensionDoesNotReplaceUnmanagedFile() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibe-island-pi-unmanaged-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let manager = PiExtensionInstallationManager(agent: .pi, agentDirectory: root)
    try FileManager.default.createDirectory(at: manager.extensionsDirectory, withIntermediateDirectories: true)
    try Data("user file".utf8).write(to: manager.extensionURL)
    #expect(throws: PiExtensionInstallationError.unmanagedExtensionExists) {
        try manager.install(extensionSourceData: Data("__OPEN_ISLAND_PI_SOURCE__".utf8))
    }
    _ = try manager.uninstall()
    #expect(try String(contentsOf: manager.extensionURL, encoding: .utf8) == "user file")
}

@Test("Pi hook command survives bridge encoding")
func piHookBridgeCommandRoundTrip() throws {
    let payload = PiHookPayload(
        hookEventName: .preToolUse,
        agent: .pi,
        sessionID: "pi-session-1",
        cwd: "/tmp/project",
        toolName: "bash",
        toolInput: "{\"command\":\"pwd\"}",
        model: "anthropic/claude-sonnet-4"
    )
    let data = try JSONEncoder().encode(BridgeCommand.processPiHook(payload))
    let decoded = try JSONDecoder().decode(BridgeCommand.self, from: data)
    #expect(decoded == .processPiHook(payload))
}

@Test("Pi socket events produce a running and then completed session")
func piSocketSessionLifecycle() async throws {
    let socketURL = BridgeSocketLocation.uniqueTestURL()
    let server = BridgeServer(socketURL: socketURL)
    try server.start()
    defer {
        server.stop()
        try? FileManager.default.removeItem(at: socketURL)
    }

    let observer = LocalBridgeClient(socketURL: socketURL)
    let events = try observer.connect()
    defer { observer.disconnect() }
    try await observer.send(.registerClient(role: .observer))
    var iterator = events.makeAsyncIterator()
    let commandClient = BridgeCommandClient(socketURL: socketURL)

    let start = PiHookPayload(
        hookEventName: .sessionStart, agent: .pi,
        sessionID: "pi-test-\(UUID().uuidString)", cwd: "/tmp/project"
    )
    #expect(try commandClient.send(.processPiHook(start), timeout: 2) == .acknowledged)
    let started = try #require(await iterator.next())
    guard case let .sessionStarted(startedPayload) = started else {
        Issue.record("Expected Pi session start")
        return
    }
    #expect(startedPayload.tool == .pi)
    #expect(startedPayload.initialPhase == .completed)

    var prompt = start
    prompt.hookEventName = .userPromptSubmit
    prompt.prompt = "Add Pi support"
    #expect(try commandClient.send(.processPiHook(prompt), timeout: 2) == .acknowledged)
    let running = try #require(await iterator.next())
    guard case let .activityUpdated(activity) = running else {
        Issue.record("Expected Pi activity update")
        return
    }
    #expect(activity.phase == .running)
    #expect(activity.summary.contains("Add Pi support"))

    var stop = start
    stop.hookEventName = .stop
    #expect(try commandClient.send(.processPiHook(stop), timeout: 2) == .acknowledged)
    let completed = try #require(await iterator.next())
    guard case let .sessionCompleted(completion) = completed else {
        Issue.record("Expected Pi session completion")
        return
    }
    #expect(completion.sessionID == start.sessionID)
}
