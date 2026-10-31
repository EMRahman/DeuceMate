// ForgottenPlayerLedgerTests.swift — "Forget player" deletion intent survives
// stale watch copies, iCloud restore and manual imports. MATCH_TAGS_PLAN.md §6.2.
import XCTest
@testable import DeuceMateCore

final class ForgottenPlayerLedgerTests: XCTestCase {

    private typealias F = TagFixtures

    private let alex = TagFixtures.player("Alex", id: TagFixtures.uuid(1))
    private let jo = TagFixtures.player("Jo", id: TagFixtures.uuid(2))
    private let sam = TagFixtures.player("Sam", id: TagFixtures.uuid(3))

    // MARK: - Value semantics and persistence

    func test_codable_storesIDsOnly_sortedAndVersioned() throws {
        let ledger = ForgottenPlayerLedger().forgetting(jo.id).forgetting(alex.id)
        let data = try JSONEncoder().encode(ledger)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("Alex"), "no names, ever")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["playerIDs"] as? [String], [alex.id.uuidString, jo.id.uuidString])
        XCTAssertEqual(try JSONDecoder().decode(ForgottenPlayerLedger.self, from: data), ledger)
    }

    func test_decode_missingOrMalformedFieldsDegradeToEmpty() throws {
        XCTAssertTrue(try JSONDecoder().decode(ForgottenPlayerLedger.self, from: Data("{}".utf8)).isEmpty)
        let partial = try JSONDecoder().decode(
            ForgottenPlayerLedger.self,
            from: Data(#"{"playerIDs":["nope","00000000-0000-0000-0000-000000000001"]}"#.utf8)
        )
        XCTAssertEqual(partial.playerIDs, [alex.id])
    }

    func test_union_withNilNeverErasesDeletionIntent() {
        let ledger = ForgottenPlayerLedger(playerIDs: [alex.id])
        XCTAssertEqual(ledger.union(nil), ledger, "an old file without a ledger cannot erase it")
        XCTAssertEqual(ledger.union(ForgottenPlayerLedger()), ledger)
        XCTAssertEqual(ledger.union(ForgottenPlayerLedger(playerIDs: [jo.id])).playerIDs, [alex.id, jo.id])
    }

    // MARK: - Scrubbing

    func test_scrubbed_removesForgottenPlayerFromEveryRole_withNewerRevision() {
        let ledger = ForgottenPlayerLedger(playerIDs: [alex.id])
        let stale = F.tags(opponents: [alex, jo], partner: alex, competition: .league, at: 10)
        let cleaned = ledger.scrubbed(stale, now: F.base.addingTimeInterval(5))
        XCTAssertEqual(cleaned.opponents, [jo])
        XCTAssertNil(cleaned.partner)
        XCTAssertEqual(cleaned.competitionType, .league, "other details survive")
        XCTAssertTrue(cleaned.supersedes(stale), "even with a lagging clock, the cleaned revision wins")
    }

    func test_scrubbed_unaffectedTagsKeepTheirRevision() {
        let ledger = ForgottenPlayerLedger(playerIDs: [alex.id])
        let tags = F.tags(opponents: [jo], at: 10, revision: F.uuid(9))
        XCTAssertEqual(ledger.scrubbed(tags, now: F.base), tags)
        let record = F.record(tags: tags)
        XCTAssertEqual(ledger.scrubbed(record, now: F.base), record)
        XCTAssertEqual(ledger.scrubbed(F.record(tags: nil), now: F.base).tags, nil)
    }

    func test_scrubbed_onlyPlayerForgotten_yieldsEmptyClear() {
        let ledger = ForgottenPlayerLedger(playerIDs: [alex.id])
        let cleaned = ledger.scrubbed(F.tags(opponents: [alex], at: 10), now: F.base.addingTimeInterval(20))
        XCTAssertTrue(cleaned.isEmpty)
        XCTAssertEqual(cleaned.updatedAt, F.base.addingTimeInterval(20))
    }

    func test_affectedMatchIDs() {
        let ledger = ForgottenPlayerLedger(playerIDs: [alex.id])
        let a = F.record(tags: F.tags(opponents: [alex]))
        let b = F.record(tags: F.tags(opponents: [jo]))
        let c = F.record(tags: F.tags(partner: alex))
        XCTAssertEqual(ledger.affectedMatchIDs(in: [a, b, c, F.record()]), [a.id, c.id])
    }

    // MARK: - Scenarios across every inbound path (§12.1 "Erasure")

    /// User forgets Alex → the watch (still holding the old tags) pushes its
    /// history → Alex does not come back, and the cleaned revision is what
    /// reconciliation sends back to the watch.
    func test_scenario_staleWatchHistoryCannotRestoreForgottenPlayer() {
        let id = UUID()
        let original = F.tags(opponents: [alex], competition: .league, at: 10)
        let phoneAfterForget = PlayerRoster.forgetting(alex.id, in: [F.record(id: id, tags: original)],
                                                       now: F.base.addingTimeInterval(20))
        let ledger = ForgottenPlayerLedger().forgetting(alex.id)
        let staleWatchCopy = F.record(id: id, tags: original)

        let merged = MatchMergePolicy.merge(
            incoming: [staleWatchCopy], into: phoneAfterForget.records,
            forgottenPlayers: ledger, now: F.base.addingTimeInterval(30)
        )
        XCTAssertEqual(merged.first?.tags?.opponents, [])
        XCTAssertEqual(merged.first?.tags?.competitionType, .league)
        XCTAssertTrue(PlayerRoster.entries(from: merged).isEmpty)

        let resend = MatchTags.pendingWatchUpdates(archive: merged, watchCopies: [staleWatchCopy], newlyHeld: [])
        XCTAssertEqual(resend.count, 1, "the watch's stale copy is cleaned by a resend")
        XCTAssertEqual(resend.first?.tags.opponents, [])
    }

    /// The phone no longer holds the match at all (e.g. it was only ever on
    /// the watch), so no newer local revision exists to win the merge — the
    /// ledger alone strips Alex, with a revision newer than the watch's.
    func test_scenario_watchOnlyMatchWithForgottenPlayer_isScrubbedOnArrival() {
        let ledger = ForgottenPlayerLedger(playerIDs: [alex.id])
        let watchCopy = F.record(tags: F.tags(opponents: [alex], partner: sam, at: 10))
        let merged = MatchMergePolicy.merge(incoming: [watchCopy], into: [], forgottenPlayers: ledger,
                                            now: F.base.addingTimeInterval(30))
        XCTAssertEqual(merged.first?.tags?.playerIDs, [sam.id])
        let resend = MatchTags.pendingWatchUpdates(archive: merged, watchCopies: [watchCopy], newlyHeld: [])
        XCTAssertEqual(resend.first?.tags.playerIDs, [sam.id])
    }

    /// User forgets Alex → reinstalls nothing, but the initial iCloud restore
    /// offers a stale backup (from before the forget) → Alex does not come back.
    func test_scenario_staleICloudRestoreCannotRestoreForgottenPlayer() {
        let backupOnly = F.record(tags: F.tags(opponents: [alex], at: 10))
        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: [], localTombstones: [],
            backupRecords: [backupOnly], backupTombstones: [],
            localForgottenPlayers: ForgottenPlayerLedger(playerIDs: [alex.id]),
            backupForgottenPlayers: nil,
            now: F.base.addingTimeInterval(30)
        )
        XCTAssertEqual(snapshot.records.first?.tags?.opponents, [])
        XCTAssertEqual(snapshot.forgottenPlayers.playerIDs, [alex.id])
    }

    /// Fresh install: the local ledger is empty but the backup carries it.
    func test_scenario_backupLedgerAppliesOnFreshInstall() {
        let backupOnly = F.record(tags: F.tags(opponents: [alex, jo], at: 10))
        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: [], localTombstones: [],
            backupRecords: [backupOnly], backupTombstones: [],
            backupForgottenPlayers: ForgottenPlayerLedger(playerIDs: [alex.id]),
            now: F.base.addingTimeInterval(30)
        )
        XCTAssertEqual(snapshot.records.first?.tags?.opponents, [jo])
        XCTAssertEqual(snapshot.forgottenPlayers.playerIDs, [alex.id])
    }

    /// Old manual archive (no ledger) imported by MERGE or REPLACE after a forget.
    func test_scenario_oldManualArchiveImport_cannotRestoreForgottenPlayer() {
        let ledger = ForgottenPlayerLedger(playerIDs: [alex.id])
        let old = F.record(tags: F.tags(opponents: [alex], at: 10))
        for mode in [ManualMatchArchiveBackup.ImportMode.merge, .replace] {
            let snapshot = ManualMatchArchiveBackup.importSnapshot(
                importing: [old], into: [], tombstones: [], mode: mode,
                currentForgottenPlayers: ledger, importedForgottenPlayers: nil,
                now: F.base.addingTimeInterval(30)
            )
            XCTAssertEqual(snapshot.records.first?.tags?.opponents, [], "\(mode)")
            XCTAssertEqual(snapshot.forgottenPlayers, ledger, "\(mode): ledger survives")
        }
    }

    func test_scenario_importedLedgerUnionsIntoCurrent_evenOnReplace() {
        let snapshot = ManualMatchArchiveBackup.importSnapshot(
            importing: [F.record(tags: F.tags(opponents: [alex, jo], at: 10))],
            into: [], tombstones: [], mode: .replace,
            currentForgottenPlayers: ForgottenPlayerLedger(playerIDs: [sam.id]),
            importedForgottenPlayers: ForgottenPlayerLedger(playerIDs: [jo.id]),
            now: F.base.addingTimeInterval(30)
        )
        XCTAssertEqual(snapshot.forgottenPlayers.playerIDs, [sam.id, jo.id])
        XCTAssertEqual(snapshot.records.first?.tags?.opponents, [alex])
    }

    func test_roster_excludesForgottenPlayersOnStaleRecords() {
        let records = [F.record(tags: F.tags(opponents: [alex, jo]))]
        let entries = PlayerRoster.entries(from: records, forgotten: ForgottenPlayerLedger(playerIDs: [alex.id]))
        XCTAssertEqual(entries.map(\.id), [jo.id])
    }
}
