import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

// MARK: - Minimal protobuf wire encoder (test-only)

private func encodeVarint(_ value: UInt64) -> [UInt8] {
    var v = value
    var out: [UInt8] = []
    repeat {
        var byte = UInt8(v & 0x7f)
        v >>= 7
        if v != 0 { byte |= 0x80 }
        out.append(byte)
    } while v != 0
    return out
}

private func tag(_ field: Int, _ wire: Int) -> [UInt8] { encodeVarint(UInt64(field << 3 | wire)) }
private func fieldVarint(_ field: Int, _ value: Int) -> [UInt8] { tag(field, 0) + encodeVarint(UInt64(value)) }
private func fieldBytes(_ field: Int, _ bytes: [UInt8]) -> [UInt8] { tag(field, 2) + encodeVarint(UInt64(bytes.count)) + bytes }
private func fieldString(_ field: Int, _ string: String) -> [UInt8] { fieldBytes(field, Array(string.utf8)) }
private func fieldMessage(_ field: Int, _ message: [UInt8]) -> [UInt8] { fieldBytes(field, message) }

/// Builds a `gen_metadata.data` blob shaped like a real Antigravity generation.
private func antigravityBlob(
    seconds: Int,
    model: String,
    input: Int,
    cacheRead: Int,
    output: Int,
    reasoning: Int,
    responseID: String
) -> [UInt8] {
    let usage = fieldVarint(2, input)
        + fieldVarint(5, cacheRead)
        + fieldVarint(9, output)
        + fieldVarint(10, reasoning)
        + fieldString(11, responseID)
    let stamp = fieldVarint(1, seconds)          // chat.#9.#4.#1 = unix seconds
    let time = fieldMessage(4, stamp)            // chat.#9.#4
    let chat = fieldMessage(4, usage)            // chat.#4 (usage)
        + fieldMessage(9, time)                  // chat.#9 (time wrapper)
        + fieldString(19, model)                 // chat.#19 (model)
    return fieldMessage(1, chat)                 // root.#1 (chatModel)
}

private func makeAntigravityDB(_ blobs: [[UInt8]]) -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("antigravity-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("conv.db").path

    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    #expect(sqlite3_exec(db, "CREATE TABLE gen_metadata (idx INTEGER, data BLOB, size INTEGER);", nil, nil, nil) == SQLITE_OK)
    var stmt: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "INSERT INTO gen_metadata (idx, data, size) VALUES (?, ?, ?);", -1, &stmt, nil) == SQLITE_OK)
    for (index, blob) in blobs.enumerated() {
        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(index))
        blob.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(stmt, 2, raw.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) // SQLITE_TRANSIENT
        }
        sqlite3_bind_int(stmt, 3, Int32(blob.count))
        #expect(sqlite3_step(stmt) == SQLITE_DONE)
    }
    sqlite3_finalize(stmt)
    sqlite3_close(db)
    return dir
}

// MARK: - ProtobufWire

@Test("ProtobufWire decodes varints, strings, and nested messages")
func protobufWireDecodes() {
    let inner = fieldVarint(2, 42) + fieldString(11, "resp-1")
    let root = fieldMessage(1, inner) + fieldString(19, "model-x")
    let message = ProtobufWire.parse(root)

    #expect(ProtobufWire.string(message, 19) == "model-x")
    let nested = ProtobufWire.message(message, 1)
    #expect(nested.flatMap { ProtobufWire.varint($0, 2) } == 42)
    #expect(nested.flatMap { ProtobufWire.string($0, 11) } == "resp-1")
}

@Test("ProtobufWire stops cleanly on truncated input")
func protobufWireTruncated() {
    // A length-delimited field claiming 10 bytes but only 2 present.
    let truncated = tag(1, 2) + encodeVarint(10) + [0x01, 0x02]
    let message = ProtobufWire.parse(truncated)
    #expect(message[1] == nil) // field not committed; no crash
}

// MARK: - Aggregator

@Test("Antigravity aggregator sums per-turn usage, de-duped by responseId")
func antigravityAggregates() {
    let now = Date()
    let cutoff = now.addingTimeInterval(-14 * 86_400)

    let turn1 = antigravityBlob(
        seconds: Int(now.addingTimeInterval(-120).timeIntervalSince1970),
        model: "gemini-default", input: 800, cacheRead: 200, output: 100, reasoning: 50, responseID: "r1"
    )
    let turn2 = antigravityBlob(
        seconds: Int(now.addingTimeInterval(-60).timeIntervalSince1970),
        model: "claude-opus-4-6-thinking", input: 500, cacheRead: 1_500, output: 20, reasoning: 5, responseID: "r2"
    )
    let outOfWindow = antigravityBlob(
        seconds: Int(now.addingTimeInterval(-30 * 86_400).timeIntervalSince1970),
        model: "gemini-default", input: 999_999, cacheRead: 0, output: 9_999, reasoning: 0, responseID: "r3"
    )

    // turn2 duplicated (same responseId) to exercise de-dup.
    let dir = makeAntigravityDB([turn1, turn2, turn2, outOfWindow])
    defer { try? FileManager.default.removeItem(at: dir) }

    let contribution = AntigravityTokenAggregator(rootURLs: [dir]).aggregate(since: cutoff, now: now)

    #expect(contribution.breakdown == TokenBreakdown(
        input: 1_300, output: 120, reasoning: 55, cacheRead: 1_700, cacheWrite: 0
    ))
    #expect(contribution.models.count == 2)
    #expect(Set(contribution.models.map(\.model)) == ["gemini-default", "claude-opus-4-6-thinking"])
    // turn1 (now-120) + turn2 (now-60) + dup (now-60) → 60s active.
    #expect(contribution.activeSeconds == 60)
}

@Test("Antigravity aggregator is empty when no conversation databases exist")
func antigravityEmpty() {
    let contribution = AntigravityTokenAggregator(rootURLs: [URL(fileURLWithPath: "/no/such/dir")])
        .aggregate(since: .distantPast, now: .now)
    #expect(contribution.breakdown == .zero)
}
