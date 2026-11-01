// MatchNotesStore.swift — the iPhone's private notes sidecar.
//
// Notes are optional free text keyed by match UUID and owned by this iPhone
// only (MATCH_TAGS_PLAN.md §4.1). They are deliberately NOT part of
// `MatchRecord`, so they can never reach WatchConnectivity, the automatic
// iCloud backup snapshot, the HTML view-model or an AI prompt by accident.
//
// Storage rules:
//   • One JSON file (Core's versioned `MatchNotesCodec`) in its OWN directory
//     under Application Support. Both the directory and the file are marked
//     excluded from device backups; the file flag is re-applied after every
//     atomic write, because an atomic write replaces the inode and drops it.
//     The directory flag is verified before any write — a write never happens
//     into a location that could be backed up.
//   • A file that exists but cannot be read or decoded is NEVER treated as
//     empty: the store refuses every write for the rest of the process and
//     surfaces `loadFailure`, so the user's notes are not overwritten.
//   • Note text is never logged. Logs carry counts and error descriptions only.
import Foundation
import Combine
import os
import DeuceMateCore

private let notesLogger = Logger(subsystem: "com.deucemate.persistence", category: "MatchNotesStore")

final class MatchNotesStore: ObservableObject {
    static let shared = MatchNotesStore()

    /// Notes by match id, including explicit clears (empty text).
    @Published private(set) var notes: [UUID: MatchNote] = [:]
    /// Non-nil when the sidecar exists but could not be read or decoded. Every
    /// write is refused while this is set, so the unreadable file survives.
    @Published private(set) var loadFailure: String?

    enum StoreError: LocalizedError, Equatable {
        /// The existing file could not be read; saving would overwrite it.
        case unreadableFile
        /// The backup-excluded directory could not be prepared, so nothing was written.
        case backupExclusionFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "Private notes on this iPhone couldn't be read, so they weren't changed. Your existing notes file has been left untouched."
            case .backupExclusionFailed:
                return "The note wasn't saved because DeuceMate couldn't keep it out of device backups."
            case .writeFailed(let reason):
                return "The note couldn't be saved: \(reason)"
            }
        }
    }

    struct Configuration {
        let directoryURL: URL
        let backupExcluder: (URL) throws -> Void

        init(directoryURL: URL, backupExcluder: ((URL) throws -> Void)? = nil) {
            self.directoryURL = directoryURL
            self.backupExcluder = backupExcluder ?? { try MatchNotesStore.excludeFromBackup($0) }
        }

        static var production: Configuration {
            Configuration(
                directoryURL: FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("MatchNotes", isDirectory: true)
            )
        }
    }

    static let filename = "matchNotes.json"

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "com.deucemate.phone.notesstore", qos: .utility)

    // MARK: Queue-confined state
    private var current: [UUID: MatchNote] = [:]
    private var writesSuspended = false

    var fileURL: URL { configuration.directoryURL.appendingPathComponent(Self.filename) }

    convenience init() {
        self.init(configuration: .production)
    }

    init(configuration: Configuration) {
        self.configuration = configuration
        let loaded = queue.sync { () -> ([UUID: MatchNote], String?) in
            let failure = loadOnQueue()
            return (current, failure)
        }
        notes = loaded.0
        loadFailure = loaded.1
    }

    // MARK: - Reading

    /// The live (non-empty) note for `matchID`, if any. Reads the queue's
    /// state, not the `@Published` mirror, so a read straight after `save` /
    /// `importNotes` sees that write (the mirror updates on a later main-queue
    /// hop; views still redraw from it).
    func note(for matchID: UUID) -> MatchNote? {
        queue.sync {
            guard let note = current[matchID], !note.isCleared else { return nil }
            return note
        }
    }

    /// Queue-consistent snapshot of every entry (tests, replace planning).
    func allNotes() -> [MatchNote] {
        queue.sync { Array(current.values) }
    }

    /// Match ids that currently carry non-empty note text.
    func matchIDsWithNotes() -> Set<UUID> {
        queue.sync { Set(current.values.filter { !$0.isCleared }.map(\.matchID)) }
    }

    // MARK: - Writing

    /// Saves `text` (sanitized; empty text is an explicit clear) for `matchID`.
    /// Returns the saved revision. Throws without changing anything when the
    /// sidecar is unreadable, the backup exclusion cannot be applied, or the
    /// write fails — the caller keeps the draft open.
    @discardableResult
    func save(text: String, for matchID: UUID, now: Date = Date()) throws -> MatchNote {
        try queue.sync {
            let edit = MatchNotesPolicy.edit(matchID: matchID, text: text, previous: current[matchID], now: now)
            var updated = current
            updated[matchID] = edit
            try persistOnQueue(updated)
            return edit
        }
    }

    /// Removes every note for `matchIDs` (permanent match deletion, or the
    /// user's explicit "delete notes on affected matches" choice).
    func removeNotes(for matchIDs: Set<UUID>) throws {
        guard !matchIDs.isEmpty else { return }
        try queue.sync {
            // The unreadable file may hold notes for these matches; report it
            // rather than claiming they were removed.
            guard !writesSuspended else { throw StoreError.unreadableFile }
            let remaining = MatchNotesPolicy.removingNotes(for: matchIDs, from: Array(current.values))
            guard remaining.count != current.count else { return }
            try persistOnQueue(Dictionary(uniqueKeysWithValues: remaining.map { ($0.matchID, $0) }))
        }
    }

    /// Restores notes from an opted-in manual archive section into the
    /// backup-excluded sidecar, merged by each note's own revision order (a
    /// newer local note is never overwritten; an included empty entry clears).
    /// Throws, changing nothing, when the sidecar is unreadable.
    func importNotes(_ incoming: [MatchNote]) throws {
        guard !incoming.isEmpty else { return }
        try queue.sync {
            guard !writesSuspended else { throw StoreError.unreadableFile }
            let merged = MatchNotesPolicy.merge(incoming, into: Array(current.values))
            try persistOnQueue(Dictionary(uniqueKeysWithValues: merged.map { ($0.matchID, $0) }))
        }
    }

    /// What replacing the archive with one holding `retainedMatchIDs` would
    /// do to notes. `discarded` lists non-empty notes that would be deleted.
    func replacePlan(retainedMatchIDs: Set<UUID>) -> MatchNotesPolicy.ReplacePlan {
        queue.sync {
            MatchNotesPolicy.replacePlan(notes: Array(current.values), retainedMatchIDs: retainedMatchIDs)
        }
    }

    /// Applies a confirmed archive replacement: keeps notes for retained ids,
    /// drops the rest (the UI has already confirmed any non-empty discards).
    func applyReplace(retainedMatchIDs: Set<UUID>) throws {
        try queue.sync {
            guard !writesSuspended else { throw StoreError.unreadableFile }
            let plan = MatchNotesPolicy.replacePlan(notes: Array(current.values), retainedMatchIDs: retainedMatchIDs)
            guard plan.retained.count != current.count else { return }
            try persistOnQueue(Dictionary(uniqueKeysWithValues: plan.retained.map { ($0.matchID, $0) }))
        }
    }

    // MARK: - Persistence

    private func persistOnQueue(_ updated: [UUID: MatchNote]) throws {
        guard !writesSuspended else { throw StoreError.unreadableFile }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: configuration.directoryURL, withIntermediateDirectories: true)
            // The directory flag is the precondition: never write note text
            // into a location that a device backup could pick up.
            try configuration.backupExcluder(configuration.directoryURL)
        } catch {
            notesLogger.error("Notes directory backup exclusion failed: \(error.localizedDescription, privacy: .public)")
            throw StoreError.backupExclusionFailed
        }
        do {
            let data = try MatchNotesCodec.encode(Array(updated.values))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            notesLogger.error("Notes write failed: \(error.localizedDescription, privacy: .public)")
            throw StoreError.writeFailed(error.localizedDescription)
        }
        // Atomic replacement drops the file's resource values; re-apply. The
        // verified directory flag above already keeps the file out of backups,
        // so a failure here is logged rather than reported as a lost save.
        do {
            try configuration.backupExcluder(fileURL)
        } catch {
            notesLogger.fault("Notes file backup exclusion failed after write: \(error.localizedDescription, privacy: .public)")
        }
        current = updated
        publishOnQueue(failure: nil)
        notesLogger.notice("Saved private notes sidecar (\(updated.count, privacy: .public) entries)")
    }

    /// Loads the sidecar. Missing ⇒ empty. Unreadable or undecodable ⇒ writes
    /// suspended and a user-facing failure returned; the file is left as-is.
    private func loadOnQueue() -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        // Reassert both flags at launch (covers migration/restore paths).
        try? configuration.backupExcluder(configuration.directoryURL)
        try? configuration.backupExcluder(fileURL)
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try MatchNotesCodec.decode(data)
            current = Dictionary(decoded.map { ($0.matchID, $0) }, uniquingKeysWith: { a, b in
                MatchNotesPolicy.merged(a, b) ?? a
            })
            return nil
        } catch {
            writesSuspended = true
            notesLogger.error("Private notes sidecar unreadable; writes suspended: \(error.localizedDescription, privacy: .public)")
            return StoreError.unreadableFile.errorDescription
        }
    }

    private func publishOnQueue(failure: String?) {
        let snapshot = current
        let suspended = writesSuspended
        DispatchQueue.main.async {
            self.notes = snapshot
            if !suspended { self.loadFailure = failure }
        }
    }

    static func excludeFromBackup(_ originalURL: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = originalURL
        try url.setResourceValues(values)
        let applied = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true
        guard applied else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSURLErrorKey: originalURL,
                NSLocalizedDescriptionKey: "Backup exclusion was not applied"
            ])
        }
    }
}
