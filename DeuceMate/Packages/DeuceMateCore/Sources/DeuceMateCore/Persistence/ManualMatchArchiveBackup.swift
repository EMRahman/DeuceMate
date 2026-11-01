// ManualMatchArchiveBackup.swift — full-fidelity user-initiated archive export/import.
import Foundation

/// Versioned JSON wrapper for manual match archive files. This is intentionally
/// separate from iCloud backup policy: manual archives are explicit user exports
/// and preserve all fields currently stored on `MatchRecord`, including
/// HealthKit-derived heart rate, steps, distance, and calories.
public enum ManualMatchArchiveBackup {
    public static let format = "deucemate.matchArchive"
    public static let supportedSchemaVersion = 1

    /// Upper bound on the raw bytes of an imported archive file. An imported file
    /// is the only genuinely externally-sourced input in the app (it may have been
    /// shared from another device or edited by hand), so we reject an absurdly
    /// large blob before handing it to the JSON decoder, which would otherwise
    /// buffer the whole thing into memory. 50 MB leaves ample headroom for a
    /// multi-season archive of full-fidelity records while still bounding worst
    /// case allocation.
    public static let maxArchiveBytes = 50_000_000

    /// Upper bound on the number of records a single import may contain. Caps
    /// post-decode work (merge/sort/persist) and UserDefaults/archive bloat from a
    /// hand-crafted file. A heavy real-world user records hundreds of matches, so
    /// 10,000 is generous defensive headroom, not a product limit.
    public static let maxArchiveRecords = 10_000

    public struct Archive: Codable, Equatable, Sendable {
        public let format: String
        public let schemaVersion: Int
        public let exportedAt: Date
        public let includesHealthData: Bool
        public let records: [MatchRecord]
        /// Forgotten-player deletion ledger (MATCH_TAGS_PLAN.md §6.2). Optional
        /// and additive within schema 1: older builds ignore the key, and an
        /// archive without it (`nil`) can never erase the importer's ledger.
        public let forgottenPlayers: ForgottenPlayerLedger?
        /// Opt-in private notes (MATCH_TAGS_PLAN.md §4.1), a separate optional
        /// section - never projected into the match JSON. `nil` (omitted) means
        /// "no information": importing it can never clear or replace a note. An
        /// included entry with empty text is an explicit clear and merges by
        /// the note's own revision order. Exported only after the user's
        /// "Include private notes" opt-in (default off).
        public let notes: [MatchNote]?

        public init(
            format: String = ManualMatchArchiveBackup.format,
            schemaVersion: Int = ManualMatchArchiveBackup.supportedSchemaVersion,
            exportedAt: Date = Date(),
            includesHealthData: Bool = true,
            records: [MatchRecord],
            forgottenPlayers: ForgottenPlayerLedger? = nil,
            notes: [MatchNote]? = nil
        ) {
            self.format = format
            self.schemaVersion = schemaVersion
            self.exportedAt = exportedAt
            self.includesHealthData = includesHealthData
            self.records = records
            self.forgottenPlayers = forgottenPlayers
            self.notes = notes
        }
    }

    public struct ImportPreview: Equatable, Sendable {
        public let recordCount: Int
        public let includesHealthData: Bool
        public let exportedAt: Date
        /// How many non-empty private notes the file carries (0 when the file
        /// has no notes section, which is the default export).
        public let noteCount: Int

        public init(recordCount: Int, includesHealthData: Bool, exportedAt: Date, noteCount: Int = 0) {
            self.recordCount = recordCount
            self.includesHealthData = includesHealthData
            self.exportedAt = exportedAt
            self.noteCount = noteCount
        }
    }

    public struct ImportSnapshot: Equatable, Sendable {
        public let records: [MatchRecord]
        public let tombstones: Set<UUID>
        /// The importer's ledger unioned with the archive's (both modes).
        public let forgottenPlayers: ForgottenPlayerLedger

        public init(
            records: [MatchRecord],
            tombstones: Set<UUID>,
            forgottenPlayers: ForgottenPlayerLedger = ForgottenPlayerLedger()
        ) {
            self.records = records
            self.tombstones = tombstones
            self.forgottenPlayers = forgottenPlayers
        }
    }

    public enum ImportMode: Equatable, Sendable {
        case merge
        case replace
    }

    public enum ArchiveError: Error, Equatable, LocalizedError, Sendable {
        case emptyFile
        case fileTooLarge
        case wrongFormat(String)
        case unsupportedSchemaVersion(Int)
        case tooManyRecords(Int)

        public var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "The archive file is empty."
            case .fileTooLarge:
                return "This archive file is too large to import."
            case .wrongFormat:
                return "This file is not a DeuceMate match archive."
            case .unsupportedSchemaVersion(let version):
                return "This DeuceMate archive version is not supported: \(version)."
            case .tooManyRecords(let count):
                return "This archive contains too many matches to import: \(count)."
            }
        }
    }

    public static func encode(
        records: [MatchRecord],
        exportedAt: Date = Date(),
        forgottenPlayers: ForgottenPlayerLedger? = nil,
        notes: [MatchNote]? = nil
    ) throws -> Data {
        let archive = Archive(
            exportedAt: exportedAt,
            records: ArchiveBackupPolicy.sortedNewestFirst(records),
            forgottenPlayers: forgottenPlayers,
            // Only notes for matches that are in this file, only when the
            // caller opted in (`nil` = omit the section entirely).
            notes: notes.map { exported in
                let ids = Set(records.map(\.id))
                return MatchNotesPolicy.merge(exported.filter { ids.contains($0.matchID) }, into: [])
            }
        )
        return try makeEncoder().encode(archive)
    }

    public static func decode(_ data: Data) throws -> Archive {
        guard !data.isEmpty else { throw ArchiveError.emptyFile }
        // Reject an oversized blob before the decoder buffers it into memory.
        guard data.count <= maxArchiveBytes else { throw ArchiveError.fileTooLarge }
        let archive = try makeDecoder().decode(Archive.self, from: data)
        try validate(archive)
        return archive
    }

    public static func preview(_ data: Data) throws -> ImportPreview {
        let archive = try decode(data)
        return ImportPreview(
            recordCount: archive.records.count,
            includesHealthData: archive.includesHealthData,
            exportedAt: archive.exportedAt,
            noteCount: archive.notes?.filter { !$0.isCleared }.count ?? 0
        )
    }

    /// The note entries an opted-in export writes for `records`: one revision
    /// per exported match, INCLUDING explicit clears. A clear must travel so
    /// importing on a phone that still holds the older note empties it; dropping
    /// it would let the stale note survive the transfer. Orphans are excluded.
    public static func exportableNotes(_ notes: [MatchNote], for records: [MatchRecord]) -> [MatchNote] {
        let ids = Set(records.map(\.id))
        return MatchNotesPolicy.merge(notes.filter { ids.contains($0.matchID) }, into: [])
    }

    /// The notes an import may restore into the backup-excluded sidecar: only
    /// entries addressed to a match the file itself carries (an orphan entry
    /// cannot create a note for a match that does not exist), one revision per
    /// match. `nil`/absent section ⇒ nothing - "no information". The caller
    /// merges the result with `MatchNotesPolicy.merge(_:into:)` so the notes'
    /// own revision order decides, in both merge and replace modes.
    public static func importableNotes(from archive: Archive) -> [MatchNote] {
        guard let notes = archive.notes else { return [] }
        let ids = Set(archive.records.map(\.id))
        return MatchNotesPolicy.merge(notes.filter { ids.contains($0.matchID) }, into: [])
    }

    /// Builds the archive state after an import. Tags merge by their own
    /// clock (via `MatchMergePolicy.resolve`) in `.merge` mode. In BOTH modes
    /// the forgotten-player ledgers union — deletion intent survives even a
    /// replace — and every resulting record is scrubbed of forgotten players,
    /// so an old archive cannot restore a forgotten name (MATCH_TAGS_PLAN.md §6.2).
    public static func importSnapshot(
        importing incoming: [MatchRecord],
        into current: [MatchRecord],
        tombstones: Set<UUID>,
        mode: ImportMode,
        currentForgottenPlayers: ForgottenPlayerLedger = ForgottenPlayerLedger(),
        importedForgottenPlayers: ForgottenPlayerLedger? = nil,
        now: Date = Date()
    ) -> ImportSnapshot {
        let incomingIDs = Set(incoming.map(\.id))
        let updatedTombstones = tombstones.subtracting(incomingIDs)
        let forgotten = currentForgottenPlayers.union(importedForgottenPlayers)

        switch mode {
        case .replace:
            return ImportSnapshot(
                records: ArchiveBackupPolicy.sortedNewestFirst(forgotten.scrubbed(incoming, now: now)),
                tombstones: updatedTombstones,
                forgottenPlayers: forgotten
            )

        case .merge:
            var byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for record in incoming {
                let resolved = MatchMergePolicy.resolve(incoming: record, existing: byID[record.id])
                byID[record.id] = resolved.fillingMissingHealthData(from: record)
            }
            return ImportSnapshot(
                records: ArchiveBackupPolicy.sortedNewestFirst(forgotten.scrubbed(Array(byID.values), now: now)),
                tombstones: updatedTombstones,
                forgottenPlayers: forgotten
            )
        }
    }

    private static func validate(_ archive: Archive) throws {
        guard archive.format == format else { throw ArchiveError.wrongFormat(archive.format) }
        guard archive.schemaVersion == supportedSchemaVersion else {
            throw ArchiveError.unsupportedSchemaVersion(archive.schemaVersion)
        }
        guard archive.records.count <= maxArchiveRecords else {
            throw ArchiveError.tooManyRecords(archive.records.count)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Match the canonical store's numeric Date encoding so manual archives
        // preserve subsecond precision.
        encoder.dateEncodingStrategy = .deferredToDate
        if #available(iOS 11.0, watchOS 4.0, macOS 10.13, *) {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.prettyPrinted]
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timeInterval = try? container.decode(TimeInterval.self) {
                return Date(timeIntervalSinceReferenceDate: timeInterval)
            }
            let string = try container.decode(String.self)
            if let date = makeFractionalISO8601Formatter().date(from: string)
                ?? makeWholeSecondISO8601Formatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Date is not a valid ISO-8601 timestamp: \(string)"
            )
        }
        return decoder
    }

    private static func makeFractionalISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeWholeSecondISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

}
