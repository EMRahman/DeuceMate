// StatsStoring.swift — shared persistence protocol and dual-format versioned JSON codec.
import Foundation

/// Forward-compatible reader/writer for persisted archive JSON arrays
/// (`matchHistory.json`, `deletedMatchIDs.json`, WatchConnectivity full-history
/// payloads).
///
/// Two-step rollout (TECHNICAL_DEBT #19):
///   1. Ship readers that accept BOTH legacy bare JSON arrays (`[...]`) and
///      versioned envelopes (`{"format": ..., "schemaVersion": ..., "items": [...]}`).
///      Writers keep emitting legacy bare arrays so older Watch/iPhone builds
///      remain readable during staggered upgrades.
///   2. In a later release, once versioned readers are deployed, writers may
///      emit versioned envelopes — and any future incompatible schema bump
///      will surface `.newerSchemaVersion` cleanly BEFORE decoding elements.
public enum PersistedArchiveCodec {
    public static let historyFormat = "deucemate.matchHistory"
    public static let tombstonesFormat = "deucemate.deletedMatchIDs"
    /// Current schema version for versioned archive envelopes.
    /// IMPORTANT: Bump this constant ONLY when introducing a shape that older
    /// schema-1 readers cannot decode (for example, a new persisted enum case
    /// or a required-field change).
    public static let currentSchemaVersion = 1
    /// Explicit range of schema versions this build knows how to decode.
    public static let supportedSchemaVersions: ClosedRange<Int> = 1...currentSchemaVersion

    public enum CodecError: Error, Equatable, LocalizedError, Sendable {
        case emptyData
        case wrongFormat(expected: String, actual: String)
        case newerSchemaVersion(version: Int, maxSupported: Int)
        case unsupportedSchemaVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .emptyData:
                return "The archive data is empty."
            case .wrongFormat(let expected, let actual):
                return "Unexpected archive format \(actual) (expected \(expected))."
            case .newerSchemaVersion(let version, let maxSupported):
                return "Archive schema version \(version) requires a newer version of DeuceMate (supports up to \(maxSupported))."
            case .unsupportedSchemaVersion(let version):
                return "Unsupported archive schema version: \(version)."
            }
        }
    }

    public struct Envelope<Items> {
        public let format: String
        public let schemaVersion: Int
        public let items: Items

        public init(
            format: String,
            schemaVersion: Int = PersistedArchiveCodec.currentSchemaVersion,
            items: Items
        ) {
            self.format = format
            self.schemaVersion = schemaVersion
            self.items = items
        }

        fileprivate enum CodingKeys: String, CodingKey {
            case format
            case schemaVersion
            case items
            case records
        }
    }

    private struct EnvelopeHeader: Decodable {
        let format: String
        let schemaVersion: Int
    }

    /// Encodes `items` in a versioned envelope. Production writers keep
    /// emitting legacy bare arrays during step 1 of the rollout.
    public static func encodeEnvelope<Items: Encodable>(
        _ items: Items,
        format: String,
        schemaVersion: Int = currentSchemaVersion,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        try encoder.encode(Envelope(format: format, schemaVersion: schemaVersion, items: items))
    }

    /// Dual-format reader accepting both legacy bare JSON arrays (`[...]`) and
    /// versioned envelopes (`{"format": ..., "schemaVersion": ..., "items": [...]}`).
    /// For JSON objects, checks `format` and `schemaVersion` BEFORE decoding
    /// `items` so a future schema version with incompatible elements always
    /// throws `.newerSchemaVersion` instead of a generic `DecodingError`.
    public static func decode<Items: Decodable>(
        _ type: Items.Type,
        from data: Data,
        expectedFormat: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Items {
        guard let firstByte = firstNonWhitespaceByte(in: data) else {
            throw CodecError.emptyData
        }
        if firstByte == UInt8(ascii: "{") {
            let header = try decoder.decode(EnvelopeHeader.self, from: data)
            guard header.format == expectedFormat else {
                throw CodecError.wrongFormat(expected: expectedFormat, actual: header.format)
            }
            if header.schemaVersion > supportedSchemaVersions.upperBound {
                throw CodecError.newerSchemaVersion(
                    version: header.schemaVersion,
                    maxSupported: supportedSchemaVersions.upperBound
                )
            }
            guard supportedSchemaVersions.contains(header.schemaVersion) else {
                throw CodecError.unsupportedSchemaVersion(header.schemaVersion)
            }
            return try decoder.decode(Envelope<Items>.self, from: data).items
        }
        return try decoder.decode(Items.self, from: data)
    }

    private static func firstNonWhitespaceByte(in data: Data) -> UInt8? {
        for byte in data {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:
                continue
            default:
                return byte
            }
        }
        return nil
    }
}

extension PersistedArchiveCodec.Envelope: Decodable where Items: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        if c.contains(.items) {
            items = try c.decode(Items.self, forKey: .items)
        } else {
            items = try c.decode(Items.self, forKey: .records)
        }
    }
}

extension PersistedArchiveCodec.Envelope: Encodable where Items: Encodable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(items, forKey: .items)
    }
}

extension PersistedArchiveCodec.Envelope: Equatable where Items: Equatable {}
extension PersistedArchiveCodec.Envelope: Sendable where Items: Sendable {}

/// Persistence boundary for completed and in-progress matches. Both the watch
/// and phone targets conform with their own file-backed implementations.
public protocol StatsStoring: AnyObject {
    func loadHistory() -> [MatchRecord]
    func saveHistory(_ records: [MatchRecord])
    func appendMatch(_ record: MatchRecord)
    func removeMatch(id: UUID)
}

// MARK: - JSON codec helpers

public extension StatsStoring {
    static func decode(_ data: Data) throws -> [MatchRecord] {
        try PersistedArchiveCodec.decode(
            [MatchRecord].self,
            from: data,
            expectedFormat: PersistedArchiveCodec.historyFormat
        )
    }

    static func encode(_ records: [MatchRecord]) throws -> Data {
        try JSONEncoder().encode(records)
    }
}
