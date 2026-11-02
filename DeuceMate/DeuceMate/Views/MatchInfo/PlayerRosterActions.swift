// PlayerRosterActions.swift — what the Players screen's name and profile
// autosaves and its Merge and Forget buttons do (MATCH_TAGS_PLAN.md §5, §6.2),
// kept out of the view so tests drive exactly the same path the screen does.
//
// Every action is store-first: the `PhoneStatsStore` mutation must be durable
// (archive AND, for Forget, the forgotten-player ledger on disk) before any
// side effect runs. If it isn't, the store has already rolled the edit back
// and this throws, so nothing is pushed to the watch, no private note is
// deleted, and the view keeps its screen open and shows the error.
import Foundation
import DeuceMateCore

struct PlayerRosterActions {
    let store: PhoneStatsStore
    let notesStore: MatchNotesStore
    let syncService: PhoneMatchSyncService

    /// Forget succeeded, but the optional private-note deletion did not.
    struct NotesNotDeletedError: LocalizedError {
        let underlying: Error

        var errorDescription: String? {
            "The player was forgotten, but their matches' private notes couldn't be deleted: \(underlying.localizedDescription)"
        }
    }

    /// Throws `PhoneStatsStore.TagEditError.notPersisted` with nothing changed.
    func rename(_ playerID: UUID, to name: String) throws {
        let affected = try store.renamePlayer(playerID, to: name)
        syncService.pushTagUpdates(forMatchIDs: affected)
    }

    /// Saves the tennis profile before notifying the watch of the updated tags.
    func updateDetails(
        _ playerID: UUID,
        handednessRaw: String?,
        backhandRaw: String?,
        playStyleRaw: String?
    ) throws {
        let affected = try store.updatePlayerDetails(
            playerID,
            handednessRaw: handednessRaw,
            backhandRaw: backhandRaw,
            playStyleRaw: playStyleRaw
        )
        syncService.pushTagUpdates(forMatchIDs: affected)
    }

    /// Throws `PhoneStatsStore.TagEditError.notPersisted` with nothing changed.
    func merge(_ duplicateID: UUID, into keptID: UUID) throws {
        let affected = try store.mergePlayers(duplicateID, into: keptID)
        syncService.pushTagUpdates(forMatchIDs: affected)
    }

    /// Forgets `playerID`, then — only once that is durable — pushes the
    /// scrubbed tags to the watch, re-scrubs the watch mirror and deletes
    /// `noteIDs`' private notes (empty ⇒ notes are kept). Throws
    /// `PhoneStatsStore.TagEditError.notPersisted` with nothing changed, or
    /// `NotesNotDeletedError` after a successful forget.
    func forget(_ playerID: UUID, deletingNotesFor noteIDs: Set<UUID> = []) throws {
        let affected = try store.forgetPlayer(playerID)
        syncService.pushTagUpdates(forMatchIDs: affected)
        // The watch mirror re-scrubs itself when the new ledger is published
        // (`PhoneMatchSyncService.ledgerObservation`).
        guard !noteIDs.isEmpty else { return }
        do {
            try notesStore.removeNotes(for: noteIDs)
        } catch {
            throw NotesNotDeletedError(underlying: error)
        }
    }
}
