// StatsStoring.swift — shared persistence protocol and JSON helpers.
import Foundation

/// Persistence boundary for completed and in-progress matches. Both the watch
/// and phone targets conform with their own file-backed implementations.
public protocol StatsStoring: AnyObject {
    func loadHistory() -> [MatchRecord]
    func saveHistory(_ records: [MatchRecord])
    func appendMatch(_ record: MatchRecord)
    func removeMatch(id: UUID)
}

// MARK: - Versioned archive envelope codec

/// Backward- and forward-compatible reader for persisted archive collections.
/// Accepts both legacy bare JSON arrays (`[MatchRecord]`, `[UUID]`) and the
/// versioned envelope (`{"format": ..., "schemaVersion": ..., "items": ...}`),
/// diagnosing `schemaVersion > currentSchemaVersion` before decoding elements so
/// an older app refuses to overwrite newer data rather than misclassifying it
/// as corruption.
public enum PersistedArchiveCodec {
    public static let historyFormat = "deucemate.matchHistory"
    public static let tombstonesFormat = "deucemate.deletedMatchIDs"
    public static let currentSchemaVersion = 1
    public static let supportedSchemaVersions: ClosedRange<Int> = 1...currentSchemaVersion

    public enum CodecError: Error, Equatable, LocalizedError, Sendable {
        case emptyFile
        case wrongFormat(String)
        case unsupportedSchemaVersion(Int)
        case newerSchemaVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "The archive file is empty."
            case .wrongFormat:
                return "This file is not a DeuceMate archive."
            case .unsupportedSchemaVersion(let version):
                return "This DeuceMate archive version is not supported: \(version)."
            case .newerSchemaVersion(let version):
                return "This archive was created by a newer version of DeuceMate (schema \(version)). Update DeuceMate to read it."
            }
        }
    }

    public struct Envelope<Items> {
        public let format: String
        public let schemaVersion: Int
        public let items: Items

        fileprivate enum CodingKeys: String, CodingKey {
            case format
            case schemaVersion
            case items
            case records
        }

        public init(
            format: String,
            schemaVersion: Int = PersistedArchiveCodec.currentSchemaVersion,
            items: Items
        ) {
            self.format = format
            self.schemaVersion = schemaVersion
            self.items = items
        }
    }

    private struct Header: Decodable {
        let format: String
        let schemaVersion: Int
    }

    public static func encodeEnvelope<T: Encodable>(
        _ items: T,
        format: String,
        schemaVersion: Int = currentSchemaVersion
    ) throws -> Data {
        try JSONEncoder().encode(
            Envelope(format: format, schemaVersion: schemaVersion, items: items)
        )
    }

    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        expectedFormat: String
    ) throws -> T {
        guard let firstByte = data.first(where: {
            $0 != 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D
        }) else {
            throw CodecError.emptyFile
        }
        let decoder = JSONDecoder()
        if firstByte == UInt8(ascii: "{") {
            let header = try decoder.decode(Header.self, from: data)
            guard header.format == expectedFormat else {
                throw CodecError.wrongFormat(header.format)
            }
            if header.schemaVersion > currentSchemaVersion {
                throw CodecError.newerSchemaVersion(header.schemaVersion)
            }
            guard supportedSchemaVersions.contains(header.schemaVersion) else {
                throw CodecError.unsupportedSchemaVersion(header.schemaVersion)
            }
            return try decoder.decode(Envelope<T>.self, from: data).items
        }
        return try decoder.decode(T.self, from: data)
    }
}

extension PersistedArchiveCodec.Envelope: Decodable where Items: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        if c.contains(.records) {
            items = try c.decode(Items.self, forKey: .records)
        } else {
            items = try c.decode(Items.self, forKey: .items)
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
