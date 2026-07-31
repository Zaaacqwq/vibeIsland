/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Combine
import Foundation

struct FilteredMediaRemoteConfiguration {
    let bundleIdentifier: String
    let acceptedBundleIdentifiers: Set<String>
    let logName: String

    static let neteaseMusic = FilteredMediaRemoteConfiguration(
        bundleIdentifier: "com.netease.163music",
        acceptedBundleIdentifiers: ["com.netease.163music"],
        logName: "NetEaseMusicController"
    )

    static let qqMusic = FilteredMediaRemoteConfiguration(
        bundleIdentifier: "com.tencent.QQMusicMac",
        acceptedBundleIdentifiers: ["com.tencent.QQMusicMac"],
        logName: "QQMusicController"
    )
}

/// A MediaRemote-backed controller that only publishes and controls one
/// configured application. This prevents a selected source from leaking stale
/// metadata or sending commands to whichever unrelated app owns Now Playing.
final class FilteredMediaRemoteController: ObservableObject, MediaControllerProtocol {
    @Published private(set) var playbackState: PlaybackState

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var isWorking: Bool {
        process?.isRunning == true
    }

    private let configuration: FilteredMediaRemoteConfiguration
    private let mediaRemoteBundle: CFBundle
    private let sendCommand: @convention(c) (Int, AnyObject?) -> Void
    private let setElapsedTime: @convention(c) (Double) -> Void
    private let setShuffleMode: @convention(c) (Int) -> Void
    private let setRepeatMode: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var targetSessionActive = false

    init?(configuration: FilteredMediaRemoteConfiguration) {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
            ),
            let sendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString
            ),
            let setElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString
            ),
            let setShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString
            ),
            let setRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString
            )
        else {
            return nil
        }

        self.configuration = configuration
        self.playbackState = Self.makeIdlePlaybackState(
            bundleIdentifier: configuration.bundleIdentifier
        )
        self.mediaRemoteBundle = bundle
        self.sendCommand = unsafeBitCast(
            sendCommandPointer,
            to: (@convention(c) (Int, AnyObject?) -> Void).self
        )
        self.setElapsedTime = unsafeBitCast(
            setElapsedTimePointer,
            to: (@convention(c) (Double) -> Void).self
        )
        self.setShuffleMode = unsafeBitCast(
            setShuffleModePointer,
            to: (@convention(c) (Int) -> Void).self
        )
        self.setRepeatMode = unsafeBitCast(
            setRepeatModePointer,
            to: (@convention(c) (Int) -> Void).self
        )

        Task { await setupNowPlayingObserver() }
    }

    deinit {
        streamTask?.cancel()

        if let pipeHandler {
            Task { await pipeHandler.close() }
        }

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
        pipeHandler = nil
    }

    func play() async {
        guard canSendCommand else { return }
        sendCommand(0, nil)
    }

    func pause() async {
        guard canSendCommand else { return }
        sendCommand(1, nil)
    }

    func togglePlay() async {
        guard canSendCommand else { return }
        sendCommand(2, nil)
    }

    func nextTrack() async {
        guard canSendCommand else { return }
        sendCommand(4, nil)
    }

    func previousTrack() async {
        guard canSendCommand else { return }
        sendCommand(5, nil)
    }

    func seek(to time: Double) async {
        guard canSendCommand, time.isFinite, time >= 0 else { return }
        setElapsedTime(time)
    }

    func toggleShuffle() async {
        guard canSendCommand else { return }
        setShuffleMode(playbackState.isShuffled ? 1 : 3)
    }

    func toggleRepeat() async {
        guard canSendCommand else { return }
        let newRepeatMode = playbackState.repeatMode == .off
            ? RepeatMode.all.rawValue
            : playbackState.repeatMode.rawValue - 1
        setRepeatMode(newRepeatMode)
    }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == configuration.bundleIdentifier
        }
    }

    func updatePlaybackInfo() async {
        // The MediaRemote stream emits an initial full snapshot and subsequent
        // diffs, so no polling request is needed.
    }

    private var canSendCommand: Bool {
        targetSessionActive && isActive()
    }

    private func setupNowPlayingObserver() async {
        let process = Process()
        guard
            let scriptURL = Bundle.main.url(
                forResource: "mediaremote-adapter",
                withExtension: "pl"
            ),
            let frameworkPath = Bundle.main.resourceURL?
                .appendingPathComponent("MediaRemoteAdapter.framework")
                .path
        else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream"]

        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { [logName = configuration.logName] handle in
            let data = handle.availableData
            guard
                !data.isEmpty,
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !message.isEmpty
            else {
                return
            }
            print("\(logName) [stderr]: \(message)")
        }

        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            assertionFailure(
                "Failed to launch mediaremote-adapter.pl for \(configuration.logName): \(error)"
            )
        }
    }

    private func processJSONStream() async {
        guard let pipeHandler else { return }

        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }
    }

    private static func makeIdlePlaybackState(bundleIdentifier: String) -> PlaybackState {
        var state = PlaybackState(bundleIdentifier: bundleIdentifier)
        state.title = String(localized: "Unknown")
        state.artist = String(localized: "Unknown")
        state.album = ""
        state.isPlaying = false
        state.artwork = nil
        state.duration = 0
        state.currentTime = 0
        state.playbackRate = 1
        state.isShuffled = false
        state.repeatMode = .off
        state.lastUpdated = Date()
        return state
    }

    private func applyIdleState() {
        targetSessionActive = false
        playbackState = Self.makeIdlePlaybackState(
            bundleIdentifier: configuration.bundleIdentifier
        )
    }

    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false
        let source = [
            payload.parentApplicationBundleIdentifier,
            payload.bundleIdentifier,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }

        if let source {
            guard configuration.acceptedBundleIdentifiers.contains(source) else {
                applyIdleState()
                return
            }
            targetSessionActive = true
        } else if !diff {
            applyIdleState()
            return
        } else if !targetSessionActive {
            return
        }

        var state = PlaybackState(bundleIdentifier: configuration.bundleIdentifier)
        state.title = payload.title ?? (diff ? playbackState.title : "")
        state.artist = payload.artist ?? (diff ? playbackState.artist : "")
        state.album = payload.album ?? (diff ? playbackState.album : "")
        state.duration = payload.duration ?? (diff ? playbackState.duration : 0)
        state.currentTime = payload.elapsedTime ?? (diff ? playbackState.currentTime : 0)
        state.playbackRate = payload.playbackRate ?? (diff ? playbackState.playbackRate : 1)
        state.isPlaying = payload.playing ?? (diff ? playbackState.isPlaying : false)

        if let shuffleMode = payload.shuffleMode {
            state.isShuffled = shuffleMode != 1
        } else {
            state.isShuffled = diff ? playbackState.isShuffled : false
        }

        if let repeatMode = payload.repeatMode {
            state.repeatMode = RepeatMode(rawValue: repeatMode) ?? .off
        } else {
            state.repeatMode = diff ? playbackState.repeatMode : .off
        }

        if let artworkData = payload.artworkData {
            state.artwork = Data(
                base64Encoded: artworkData.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if diff {
            state.artwork = playbackState.artwork
        }

        if let timestamp = payload.timestamp,
           let date = ISO8601DateFormatter().date(from: timestamp) {
            state.lastUpdated = date
        } else {
            state.lastUpdated = diff ? playbackState.lastUpdated : Date()
        }

        playbackState = state
    }
}
