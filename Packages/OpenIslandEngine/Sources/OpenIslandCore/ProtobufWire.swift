import Foundation

/// A minimal, dependency-free Protocol Buffers *wire-format* reader.
///
/// Antigravity stores each generation's metadata as a `GeneratorMetadata`
/// protobuf blob in the `gen_metadata` table, but ships no `.proto` schema — the
/// IDE receives JSON from its language server, and the CLI persists the raw
/// wire bytes. This reader decodes just enough of the wire format (it does not
/// know the schema) to walk to the handful of fields the token aggregator needs.
///
/// It is deliberately permissive: an unknown wire type or a truncated field
/// stops parsing and returns whatever was decoded so far, so a
/// forward-incompatible record degrades to partial/empty rather than crashing.
public enum ProtobufWire {
    /// One decoded field value. Length-delimited payloads (`bytes`) may be a
    /// UTF-8 string or a nested message — the caller decides by re-parsing.
    public enum Value {
        case varint(UInt64)
        case bytes([UInt8])
        case fixed64(UInt64)
        case fixed32(UInt32)
    }

    /// Decoded message: field number → values in encounter order. Repeated
    /// fields accumulate; callers usually take the first.
    public typealias Message = [Int: [Value]]

    /// Parses a protobuf message from raw bytes. Never throws.
    public static func parse(_ bytes: [UInt8]) -> Message {
        var message: Message = [:]
        var index = 0
        let count = bytes.count

        func readVarint() -> UInt64? {
            var shift: UInt64 = 0
            var value: UInt64 = 0
            while index < count {
                let byte = bytes[index]
                index += 1
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
                if shift >= 64 { return nil }
            }
            return nil
        }

        while index < count {
            guard let tag = readVarint() else { break }
            let field = Int(tag >> 3)
            let wireType = tag & 0x7

            switch wireType {
            case 0: // varint
                guard let value = readVarint() else { return message }
                message[field, default: []].append(.varint(value))
            case 1: // 64-bit
                guard index + 8 <= count else { return message }
                var value: UInt64 = 0
                for offset in 0..<8 { value |= UInt64(bytes[index + offset]) << (8 * offset) }
                index += 8
                message[field, default: []].append(.fixed64(value))
            case 2: // length-delimited
                guard let length = readVarint() else { return message }
                let byteCount = Int(length)
                guard byteCount >= 0, index + byteCount <= count else { return message }
                message[field, default: []].append(.bytes(Array(bytes[index..<index + byteCount])))
                index += byteCount
            case 5: // 32-bit
                guard index + 4 <= count else { return message }
                var value: UInt32 = 0
                for offset in 0..<4 { value |= UInt32(bytes[index + offset]) << (8 * offset) }
                index += 4
                message[field, default: []].append(.fixed32(value))
            default: // start/end group (deprecated) or unknown — stop cleanly
                return message
            }
        }
        return message
    }

    // MARK: - Field accessors (first value wins)

    /// The first varint value of `field`, if present.
    public static func varint(_ message: Message, _ field: Int) -> UInt64? {
        guard case let .varint(value)? = message[field]?.first else { return nil }
        return value
    }

    /// The first length-delimited value of `field` decoded as a nested message.
    public static func message(_ message: Message, _ field: Int) -> Message? {
        guard case let .bytes(bytes)? = message[field]?.first else { return nil }
        return parse(bytes)
    }

    /// The first length-delimited value of `field` decoded as a UTF-8 string.
    public static func string(_ message: Message, _ field: Int) -> String? {
        guard case let .bytes(bytes)? = message[field]?.first else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
}
