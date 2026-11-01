// MatchNotes.swift — pure codec and policy for the iPhone's private notes sidecar.
//
// Notes are phone-owned free text keyed by match UUID. They are deliberately
// NOT a field on `MatchRecord` or `MatchTags`: they never enter
// WatchConnectivity, the automatic iCloud snapshot, the HTML view-model or an
// AI prompt implicitly, because prose can contain health information
// ("my knee injury worsened"). The iOS `MatchNotesStore` (PR 3) owns the
// file, its backup exclusion and serialized writes; this file owns the format,
// the text rules and the merge/replace policy. See MATCH_TAGS_PLAN.md §4.1.
import Foundation

// MARK: - MatchNote

/// One match's private note. Empty `text` is an explicit clear (a newer empty
/// revision beats an older non-empty one), mirroring `MatchTags`.
public struct MatchNote: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { matchID }

    public let matchID: UUID
    /// Sanitized by `MatchNotesPolicy.sanitizedText(_:)`.
    public var text: String
    /// Note-only last-write-wins clock.
    public var updatedAt: Date
    /// Deterministic tie-break for equal clocks (larger `uuidString` wins).
    public var revisionID: UUID

    public init(matchID: UUID, text: String, updatedAt: Date, revisionID: UUID = UUID()) {
        self.matchID = matchID
        self.text = text
        self.updatedAt = updatedAt
        self.revisionID = revisionID
    }

    /// `matchID` is required (an entry without one is unaddressable); every
    /// other field is `decodeIfPresent` + default, and text is re-sanitized.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchID = try c.decode(UUID.self, forKey: .matchID)
        text = MatchNotesPolicy.sanitizedText(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        revisionID = try c.decodeIfPresent(UUID.self, forKey: .revisionID) ?? MatchTags.legacyRevisionID
    }

    /// `true` for an explicit clear.
    public var isCleared: Bool { text.isEmpty }

    /// Same strict revision order as `MatchTags.supersedes`: later clock, then
    /// larger revision id, then text — so merges commute.
    public func supersedes(_ other: MatchNote) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        if revisionID != other.revisionID { return revisionID.uuidString > other.revisionID.uuidString }
        return text > other.text
    }
}

// MARK: - Policy

public enum MatchNotesPolicy {
    /// Editor cap, in characters.
    public static let maxLength = 4_000

    /// Normalises line endings to `\n` (CRLF, CR, U+2028/U+2029, NEL), keeps
    /// paragraph breaks and tabs, strips every other nonprinting control
    /// character and bidirectional-override character, trims leading/trailing
    /// whitespace, and caps at `maxLength` characters. Whitespace-only text
    /// becomes `""` (a clear). Idempotent.
    public static func sanitizedText(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
        var scalars = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars {
            if scalar == "\n" || scalar == "\t" {
                scalars.append(scalar)
            } else if MatchTags.isLineBreak(scalar) {
                scalars.append("\n")
            } else if scalar.properties.generalCategory == .control || MatchTags.isBidiControl(scalar) {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A local save of `text` for `matchID`: sanitized, stamped strictly after
    /// `previous` even if the clock moved backwards, with a fresh revision.
    /// Saving empty text produces an explicit clear.
    public static func edit(
        matchID: UUID,
        text: String,
        previous: MatchNote?,
        now: Date = Date(),
        revisionID: UUID = UUID()
    ) -> MatchNote {
        let floor = previous.map { $0.updatedAt.addingTimeInterval(MatchTags.minimumClockStep) }
        return MatchNote(
            matchID: matchID,
            text: sanitizedText(text),
            updatedAt: max(now, floor ?? now),
            revisionID: revisionID
        )
    }

    /// Revision merge for one match: `nil` = no information; otherwise the
    /// superseding revision. Commutative.
    public static func merged(_ existing: MatchNote?, _ incoming: MatchNote?) -> MatchNote? {
        switch (existing, incoming) {
        case (nil, nil): return nil
        case (let e?, nil): return e
        case (nil, let i?): return i
        case (let e?, let i?): return i.supersedes(e) ? i : e
        }
    }

    /// Merges `incoming` notes (e.g. an opted-in manual-archive section) into
    /// `current` by each note's own revision order. Notes for other matches are
    /// preserved untouched. Result is one entry per match id, sorted by id.
    public static func merge(_ incoming: [MatchNote], into current: [MatchNote]) -> [MatchNote] {
        var byID: [UUID: MatchNote] = [:]
        for note in current + incoming {
            byID[note.matchID] = merged(byID[note.matchID], note)
        }
        return sortedByID(Array(byID.values))
    }

    /// Notes left after permanently deleting `deletedMatchIDs` (permanent match
    /// deletion removes that match's notes).
    public static func removingNotes(for deletedMatchIDs: Set<UUID>, from notes: [MatchNote]) -> [MatchNote] {
        notes.filter { !deletedMatchIDs.contains($0.matchID) }
    }

    /// The effect of replacing the archive with one holding `retainedMatchIDs`:
    /// notes for retained ids are kept; notes for removed ids are listed in
    /// `discarded` so the UI can confirm before dropping them (never silently).
    public struct ReplacePlan: Equatable, Sendable {
        public let retained: [MatchNote]
        /// Non-empty notes that would be lost. Cleared entries are not counted.
        public let discarded: [MatchNote]
        public var requiresConfirmation: Bool { !discarded.isEmpty }
    }

    public static func replacePlan(notes: [MatchNote], retainedMatchIDs: Set<UUID>) -> ReplacePlan {
        let sorted = sortedByID(notes)
        return ReplacePlan(
            retained: sorted.filter { retainedMatchIDs.contains($0.matchID) },
            discarded: sorted.filter { !retainedMatchIDs.contains($0.matchID) && !$0.isCleared }
        )
    }

    private static func sortedByID(_ notes: [MatchNote]) -> [MatchNote] {
        notes.sorted { $0.matchID.uuidString < $1.matchID.uuidString }
    }
}

// MARK: - Codec

/// Versioned file format for the notes sidecar (and, later, the opt-in notes
/// section of a manual archive). Decoding is strict: a corrupt, foreign or
/// newer-than-supported file THROWS — the store must surface it and never
/// treat it as empty and overwrite it.
public enum MatchNotesCodec {
    public static let format = "deucemate.matchNotes"
    public static let currentSchemaVersion = 1

    public struct File: Codable, Equatable, Sendable {
        public let format: String
        public let schemaVersion: Int
        public let notes: [MatchNote]

        public init(
            format: String = MatchNotesCodec.format,
            schemaVersion: Int = MatchNotesCodec.currentSchemaVersion,
            notes: [MatchNote]
        ) {
            self.format = format
            self.schemaVersion = schemaVersion
            self.notes = notes
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            format = try c.decode(String.self, forKey: .format)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            // `notes` is schema 1's foundational payload, not an additive field:
            // missing or null must THROW so a malformed sidecar is never read
            // as an intentionally empty one (`[]`) and overwritten on save.
            notes = try c.decode([MatchNote].self, forKey: .notes)
        }
    }

    public enum CodecError: Error, Equatable, Sendable {
        case emptyFile
        case wrongFormat(String)
        case unsupportedSchemaVersion(Int)
    }

    /// Encodes `notes` (deduplicated by revision, sorted by match id) with
    /// numeric dates, matching the canonical archive.
    public static func encode(_ notes: [MatchNote]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(File(notes: MatchNotesPolicy.merge(notes, into: [])))
    }

    /// Decodes a sidecar. Throws on empty data, a foreign format, a schema
    /// newer than this build supports, or malformed JSON. Duplicate entries for
    /// one match collapse to their superseding revision.
    public static func decode(_ data: Data) throws -> [MatchNote] {
        guard !data.isEmpty else { throw CodecError.emptyFile }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let file = try decoder.decode(File.self, from: data)
        guard file.format == format else { throw CodecError.wrongFormat(file.format) }
        guard file.schemaVersion <= currentSchemaVersion else {
            throw CodecError.unsupportedSchemaVersion(file.schemaVersion)
        }
        return MatchNotesPolicy.merge(file.notes, into: [])
    }
}
