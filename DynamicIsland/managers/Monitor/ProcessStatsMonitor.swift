/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
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
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Darwin
import Foundation

/// One process in a "top processes" list.
struct ProcessSample: Identifiable, Equatable, Sendable {
    let id: pid_t
    let name: String
    /// CPU percent, resident bytes, or download bytes/second.
    let value: Double
    /// Second figure for two-column lists — the network card's upload rate.
    var secondary: Double?
}

/// Top-process lists for the CPU, Memory and Network detail cards.
///
/// **Why these run as subprocesses.** The obvious in-process route
/// (`proc_listpids` + `proc_pid_rusage`) only works for processes owned by the
/// current user: for anything else `proc_pid_rusage` returns -1 and
/// `proc_pidinfo` returns 0 bytes, verified against WindowServer (uid 88). That
/// silently dropped WindowServer, coreaudiod, bluetoothd and every other system
/// daemon — usually the heaviest entries in the list. `ps` and `top` read the
/// same figures through `sysctl`, which is not privilege-gated, so they see the
/// whole machine. Both are cheap (`ps` ~10ms, `top -l 1` ~390ms).
///
/// **What runs when.** `ps` and `top` report absolute figures, so the CPU and
/// memory lists are correct from their very first sample and only run while
/// their own detail view is open — that keeps the expensive one (`top`, ~0.45s
/// of CPU per run) off the overview grid, which shows no process list at all.
/// `nettop` is the exception: its counters are cumulative, so a rate needs two
/// runs ~11s apart. That one starts with the tab, which it can afford — it
/// costs ~0.03s of CPU per run and spends the rest of its 5s asleep.
///
/// The published lists survive a stop, so re-opening a card shows the last
/// known values immediately and refreshes over them.
@MainActor
final class ProcessStatsMonitor: ObservableObject {
    static let shared = ProcessStatsMonitor()

    enum Metric: Hashable {
        case cpu
        case memory
        case network
    }

    @Published private(set) var topCPU: [ProcessSample] = []
    @Published private(set) var topMemory: [ProcessSample] = []
    @Published private(set) var topNetwork: [ProcessSample] = []
    /// True until two `nettop` runs have completed — rates need a baseline, and
    /// each run takes ~5s, so the card says so rather than looking broken.
    @Published private(set) var isLoadingNetwork = false

    /// Rows each card has room for. `nonisolated` so the detached samplers can
    /// read it without hopping to the main actor.
    nonisolated static let listLimit = 5

    /// `ps` costs ~0.01s per run, so the CPU list can refresh every second.
    private let cpuPollInterval: TimeInterval = 1
    /// `top` costs ~0.45s of CPU per run — by far the most expensive sampler
    /// here — and process footprints barely move second to second, so this one
    /// stays slower.
    private let memoryPollInterval: TimeInterval = 2
    /// `nettop` blocks ~5s per run regardless of its own interval flags, so the
    /// gap on top of that is kept short; the effective period is ~6s.
    private let networkPollInterval: TimeInterval = 1

    private let sampler = ProcessSampler()
    private var cpuTask: Task<Void, Never>?
    private var memoryTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func start(_ metric: Metric) {
        switch metric {
        case .cpu: startCPU()
        case .memory: startMemory()
        case .network: startNetwork()
        }
    }

    func stop(_ metric: Metric) {
        switch metric {
        case .cpu:
            cpuTask?.cancel()
            cpuTask = nil
        case .memory:
            memoryTask?.cancel()
            memoryTask = nil
        case .network:
            networkTask?.cancel()
            networkTask = nil
            isLoadingNetwork = false
        }
    }

    func stopAll() {
        stop(.cpu)
        stop(.memory)
        stop(.network)
    }

    private func startCPU() {
        guard cpuTask == nil else { return }
        cpuTask = Task { [weak self] in
            guard let self else { return }
            await self.tickCPU()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.cpuPollInterval))
                } catch {
                    break
                }
                await self.tickCPU()
            }
        }
    }

    private func startMemory() {
        guard memoryTask == nil else { return }
        memoryTask = Task { [weak self] in
            guard let self else { return }
            await self.tickMemory()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.memoryPollInterval))
                } catch {
                    break
                }
                await self.tickMemory()
            }
        }
    }

    private func startNetwork() {
        guard networkTask == nil else { return }
        isLoadingNetwork = topNetwork.isEmpty
        networkTask = Task { [weak self] in
            guard let self else { return }
            await self.tickNetwork()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.networkPollInterval))
                } catch {
                    break
                }
                await self.tickNetwork()
            }
        }
    }

    // MARK: - Ticks

    private func tickCPU() async {
        let limit = Self.listLimit
        let rows = await Task.detached(priority: .utility) {
            ProcessSampler.topCPU(limit: limit)
        }.value
        guard !Task.isCancelled, !rows.isEmpty, rows != topCPU else { return }
        topCPU = rows
    }

    private func tickMemory() async {
        let limit = Self.listLimit
        let rows = await Task.detached(priority: .utility) {
            ProcessSampler.topMemory(limit: limit)
        }.value
        guard !Task.isCancelled, !rows.isEmpty, rows != topMemory else { return }
        topMemory = rows
    }

    private func tickNetwork() async {
        // nil means "no baseline yet" — distinct from "measured, nothing moving".
        guard let rows = await sampler.networkRates(limit: Self.listLimit) else { return }
        guard !Task.isCancelled else { return }
        isLoadingNetwork = false
        if rows != topNetwork { topNetwork = rows }
    }
}

/// Process-list sampling. Owns the previous `nettop` totals that turn its
/// cumulative counters into per-second rates; the CPU and memory readers are
/// stateless and hang off this type only for namespacing.
actor ProcessSampler {
    private var previousNet: [pid_t: (inBytes: Double, outBytes: Double)] = [:]
    private var previousNetTime: Date?

    // MARK: - CPU

    /// `ps -r` sorts by CPU descending and covers every user's processes.
    /// Its `%CPU` is a decaying average rather than an instantaneous reading —
    /// the same figure Activity Monitor and Stats show.
    nonisolated static func topCPU(limit: Int) -> [ProcessSample] {
        guard let output = run("/bin/ps", ["-Aceo", "pid,pcpu,comm", "-r"]) else { return [] }
        var rows: [ProcessSample] = []
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3,
                  let pid = pid_t(fields[0]),
                  let percent = Double(fields[1]) else { continue }
            let name = fields.dropFirst(2).joined(separator: " ")
            guard !name.isEmpty else { continue }
            rows.append(ProcessSample(id: pid, name: name, value: percent, secondary: nil))
            if rows.count == limit { break }
        }
        return rows
    }

    // MARK: - Memory

    /// `top`'s MEM column is the physical footprint — the figure Activity
    /// Monitor's Memory column shows. `ps`'s RSS is not the same thing and
    /// under-reports processes like WindowServer badly.
    ///
    /// `top` truncates the command column no matter how wide the output is, so
    /// the names come from a `ps` lookup joined on pid instead.
    nonisolated static func topMemory(limit: Int) -> [ProcessSample] {
        guard let output = run(
            "/usr/bin/top",
            ["-l", "1", "-o", "mem", "-n", "\(limit)", "-stats", "pid,mem"]
        ) else { return [] }

        let names = nameMap()
        var rows: [ProcessSample] = []
        var reachedTable = false
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard reachedTable else {
                if trimmed.hasPrefix("PID") { reachedTable = true }
                continue
            }
            let fields = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2,
                  let pid = pid_t(fields[0]),
                  let bytes = parseSize(String(fields[1])) else { continue }
            rows.append(
                ProcessSample(id: pid, name: names[pid] ?? "pid \(pid)", value: bytes, secondary: nil)
            )
            if rows.count == limit { break }
        }
        return rows
    }

    /// Full process names for every pid, via one cheap `ps` call.
    nonisolated static func nameMap() -> [pid_t: String] {
        guard let output = run("/bin/ps", ["-Aceo", "pid,comm"]) else { return [:] }
        var map: [pid_t: String] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = pid_t(trimmed[..<space]) else { continue }
            let name = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { map[pid] = name }
        }
        return map
    }

    /// `top` sizes like "1108M", "4096K", "1.2G".
    nonisolated static func parseSize(_ text: String) -> Double? {
        guard let last = text.last else { return nil }
        let multipliers: [Character: Double] = [
            "B": 1, "K": 1024, "M": 1_048_576, "G": 1_073_741_824, "T": 1_099_511_627_776,
        ]
        if let multiplier = multipliers[Character(last.uppercased())] {
            guard let number = Double(text.dropLast()) else { return nil }
            return number * multiplier
        }
        return Double(text)
    }

    // MARK: - Network

    /// Per-process download/upload rates.
    ///
    /// macOS exposes no per-process network counters through a public API, so
    /// this shells out to `nettop`, whose counters are cumulative since each
    /// process started. Two runs are therefore needed before any rate exists —
    /// that is what the nil return means.
    ///
    /// Returns an empty array once a baseline exists but nothing is moving.
    func networkRates(limit: Int) -> [ProcessSample]? {
        let now = Date()
        let totals = Self.nettopTotals()
        guard !totals.isEmpty else { return nil }

        let previous = previousNet
        let previousTime = previousNetTime
        previousNet = totals.mapValues { ($0.inBytes, $0.outBytes) }
        previousNetTime = now

        guard let previousTime, !previous.isEmpty else { return nil }
        let elapsed = now.timeIntervalSince(previousTime)
        guard elapsed > 0.5 else { return nil }

        let names = Self.nameMap()
        var rows: [ProcessSample] = []
        for (pid, current) in totals {
            guard let prior = previous[pid] else { continue }
            // Counters only ever climb; a decrease means the pid was recycled.
            let down = max(current.inBytes - prior.inBytes, 0) / elapsed
            let up = max(current.outBytes - prior.outBytes, 0) / elapsed
            guard down > 0 || up > 0 else { continue }
            rows.append(
                ProcessSample(id: pid, name: names[pid] ?? current.name, value: down, secondary: up)
            )
        }

        // Idle processes are dropped rather than padding the list with zeroes:
        // which zero-rate process would fill the remaining rows is arbitrary.
        return Array(
            rows.sorted { ($0.value + ($0.secondary ?? 0)) > ($1.value + ($1.secondary ?? 0)) }
                .prefix(limit)
        )
    }

    /// Cumulative bytes in/out per process from `nettop`, keyed by pid.
    private nonisolated static func nettopTotals() -> [pid_t: (inBytes: Double, outBytes: Double, name: String)] {
        guard let output = run(
            "/usr/bin/nettop",
            ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-x"]
        ) else { return [:] }

        var result: [pid_t: (inBytes: Double, outBytes: Double, name: String)] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            // nettop labels rows "name.pid"; the name itself may contain dots
            // ("com.cisco.anyco.550"), so split at the *last* one.
            let label = String(fields[0])
            guard let dot = label.lastIndex(of: "."),
                  let pid = pid_t(label[label.index(after: dot)...]) else { continue }
            let inBytes = Double(fields[1]) ?? 0
            let outBytes = Double(fields[2]) ?? 0
            // A pid can appear on several rows (one per interface); sum them.
            let existing = result[pid]
            result[pid] = (
                inBytes: (existing?.inBytes ?? 0) + inBytes,
                outBytes: (existing?.outBytes ?? 0) + outBytes,
                name: existing?.name ?? String(label[..<dot])
            )
        }
        return result
    }

    // MARK: - Subprocess helper

    private nonisolated static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting: a full pipe buffer would deadlock the child.
        let data = try? pipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
