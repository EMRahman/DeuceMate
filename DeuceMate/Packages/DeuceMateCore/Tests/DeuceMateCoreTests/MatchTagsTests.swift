// MatchTagsTests.swift — the match-tags model: persisted identifiers, the
// tag-clock merge table, sanitizing, editing and §6.1 reconciliation.
// See docs/features/MATCH_TAGS_PLAN.md §3, §4, §6.1.
import XCTest
@testable import DeuceMateCore

final class MatchTagsTests: XCTestCase {

    private typealias F = TagFixtures

    func test_playerProfile_decodeSanitizeAndRoundTrip() throws {
        let id = F.uuid(1)
        let old = try JSONDecoder().decode(TaggedPlayer.self, from: Data("{\"id\":\"\(id)\",\"name\":\"Alex\"}".utf8))
        XCTAssertNil(old.handednessRaw)
        XCTAssertNil(old.backhandRaw)
        XCTAssertNil(old.playStyleRaw)
        XCTAssertNil(old.profileSummary)

        let malformed = try JSONDecoder().decode(
            TaggedPlayer.self,
            from: Data("{\"id\":\"\(id)\",\"name\":\"Alex\",\"handednessRaw\":42,\"backhandRaw\":true,\"playStyleRaw\":[]}".utf8)
        )
        XCTAssertNil(malformed.handednessRaw)
        XCTAssertNil(malformed.backhandRaw)
        XCTAssertNil(malformed.playStyleRaw)

        let control = TaggedPlayer(
            id: id,
            name: "Alex",
            handednessRaw: "left\u{0007}",
            backhandRaw: "   ",
            playStyleRaw: String(repeating: "x", count: 100)
        )
        XCTAssertNil(control.handednessRaw, "control characters are rejected")
        XCTAssertNil(control.backhandRaw, "whitespace-only raw becomes nil")
        XCTAssertEqual(control.playStyleRaw?.count, TaggedPlayer.maxAttributeRawLength)

        let future = TaggedPlayer(
            id: id,
            name: "Alex",
            handednessRaw: "ambidextrous",
            backhandRaw: "twoHandedSlice",
            playStyleRaw: "chipAndCharge"
        )
        XCTAssertNil(future.handedness)
        XCTAssertNil(future.backhand)
        XCTAssertNil(future.playStyle)
        XCTAssertNil(future.profileSummary, "unknown future raw values are kept without fabricating labels")
        let roundTripped = try JSONDecoder().decode(TaggedPlayer.self, from: JSONEncoder().encode(future))
        XCTAssertEqual(roundTripped, future)

        var typed = TaggedPlayer(id: id, name: "Alex")
        typed.handedness = .leftHanded
        typed.backhand = .oneHanded
        typed.playStyle = .serveAndVolley
        XCTAssertEqual(typed.handednessRaw, "leftHanded")
        XCTAssertEqual(typed.backhandRaw, "oneHanded")
        XCTAssertEqual(typed.playStyleRaw, "serveAndVolley")
        XCTAssertEqual(typed.profileSummary, "Left-handed · One-handed backhand · Serve & Volley")

        typed.handednessRaw = "  "
        XCTAssertNil(F.tags(opponents: [typed]).sanitized().opponents.first?.handednessRaw)
    }

    func test_playerProfile_rawValuesAndLabelsArePinned() {
        XCTAssertEqual(PlayerHandedness.rightHanded.rawValue, "rightHanded")
        XCTAssertEqual(PlayerHandedness.leftHanded.rawValue, "leftHanded")
        XCTAssertEqual(PlayerHandedness.allCases.map(\.displayLabel), ["Right-handed", "Left-handed"])

        XCTAssertEqual(PlayerBackhand.twoHanded.rawValue, "twoHanded")
        XCTAssertEqual(PlayerBackhand.oneHanded.rawValue, "oneHanded")
        XCTAssertEqual(PlayerBackhand.allCases.map(\.displayLabel), ["Two-handed", "One-handed"])

        XCTAssertEqual(PlayerPlayStyle.allCourt.rawValue, "allCourt")
        XCTAssertEqual(PlayerPlayStyle.aggressiveBaseliner.rawValue, "aggressiveBaseliner")
        XCTAssertEqual(PlayerPlayStyle.counterpuncher.rawValue, "counterpuncher")
        XCTAssertEqual(PlayerPlayStyle.serveAndVolley.rawValue, "serveAndVolley")
        XCTAssertEqual(PlayerPlayStyle.pusher.rawValue, "pusher")
        XCTAssertEqual(
            PlayerPlayStyle.allCases.map(\.displayLabel),
            ["All-Court", "Aggressive Baseliner", "Counterpuncher", "Serve & Volley", "Pusher"]
        )
    }

    func test_playerProfile_breaksEqualClockTiesCommutatively() {
        let a = F.tags(
            opponents: [TaggedPlayer(id: F.uuid(1), name: "Alex", handednessRaw: "rightHanded")],
            at: 10,
            revision: MatchTags.legacyRevisionID
        )
        var b = a
        b.opponents[0].handedness = .leftHanded
        XCTAssertEqual(MatchTags.merged(a, b), MatchTags.merged(b, a))
        XCTAssertNotEqual(a.supersedes(b), b.supersedes(a))
    }

    func test_playerProfile_survivesWireAndManualArchive() throws {
        let player = TaggedPlayer(
            id: F.uuid(1),
            name: "Alex",
            handednessRaw: "leftHanded",
            backhandRaw: "oneHanded",
            playStyleRaw: "futureStyle"
        )
        let tags = F.tags(opponents: [player], at: 1)
        let record = F.record(tags: tags)
        let payload = try MatchSyncPayloadBuilder.matchTagsUpdate(matchID: record.id, tags: tags)
        XCTAssertEqual(SyncIncomingPayload.decode(payload), [.matchTagsUpdate(matchID: record.id, tags: tags)])
        let data = try ManualMatchArchiveBackup.encode(records: [record])
        let restored = try ManualMatchArchiveBackup.decode(data)
        XCTAssertEqual(restored.records.first?.tags?.opponents.first, player)
    }

    // MARK: - Persisted identifiers

    /// The raw values reach every archive, backup and the wire. Renaming one
    /// silently turns every stored competition into "unknown". Never edit
    /// these expectations — add a case instead (CLAUDE.md §4, OQ-4).
    func test_competitionType_rawValuesArePersistedIdentifiers() {
        XCTAssertEqual(CompetitionType.friendly.rawValue, "friendly")
        XCTAssertEqual(CompetitionType.league.rawValue, "league")
        XCTAssertEqual(CompetitionType.tournament.rawValue, "tournament")
        XCTAssertEqual(CompetitionType.practice.rawValue, "practice")
        XCTAssertEqual(CompetitionType.allCases.count, 4)
    }

    func test_competitionType_displayLabels() {
        XCTAssertEqual(CompetitionType.allCases.map(\.displayLabel),
                       ["Friendly", "League", "Tournament", "Practice"])
    }

    func test_matchTagsUpdate_wireKeyIsPinned() {
        XCTAssertEqual(MatchSyncKey.matchTagsUpdate, "matchTagsUpdate")
    }

    func test_legacyRevisionID_isTheZeroUUID() {
        XCTAssertEqual(MatchTags.legacyRevisionID.uuidString, "00000000-0000-0000-0000-000000000000")
    }

    // MARK: - Unknown competition (forward compatibility)

    func test_unknownCompetition_decodesAsNilAndReencodesRawUnchanged() throws {
        let json = """
        {"opponents":[],"competitionTypeRaw":"ladder","updatedAt":10,
         "revisionID":"00000000-0000-0000-0000-000000000001"}
        """.data(using: .utf8)!
        let tags = try JSONDecoder().decode(MatchTags.self, from: json)
        XCTAssertNil(tags.competitionType)
        XCTAssertEqual(tags.competitionTypeRaw, "ladder")
        XCTAssertFalse(tags.isEmpty, "an unknown competition is still information")

        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tags)) as? [String: Any]
        XCTAssertEqual(reencoded?["competitionTypeRaw"] as? String, "ladder")
    }

    func test_competitionType_setterWritesRaw() {
        var tags = F.tags()
        tags.competitionType = .league
        XCTAssertEqual(tags.competitionTypeRaw, "league")
        tags.competitionType = nil
        XCTAssertNil(tags.competitionTypeRaw)
    }

    // MARK: - Lenient decoding

    func test_decode_missingFieldsUseDefaults() throws {
        let tags = try JSONDecoder().decode(MatchTags.self, from: Data("{}".utf8))
        XCTAssertTrue(tags.isEmpty)
        XCTAssertEqual(tags.updatedAt, .distantPast)
        XCTAssertEqual(tags.revisionID, MatchTags.legacyRevisionID)
    }

    func test_decode_malformedPlayerIsDroppedNotFatal() throws {
        let json = """
        {"opponents":[{"name":"No id"},
                      {"id":"00000000-0000-0000-0000-000000000009","name":"Alex"}],
         "partner":"not an object","updatedAt":"not a date"}
        """.data(using: .utf8)!
        let tags = try JSONDecoder().decode(MatchTags.self, from: json)
        XCTAssertEqual(tags.opponents.map(\.name), ["Alex"])
        XCTAssertNil(tags.partner)
        XCTAssertEqual(tags.updatedAt, .distantPast)
    }

    func test_codable_roundTripsEveryField() throws {
        let tags = F.tags(opponents: [F.player("Alex"), F.player("Jo")], partner: F.player("Sam"),
                          competition: .tournament, at: 42, revision: F.uuid(7))
        let decoded = try JSONDecoder().decode(MatchTags.self, from: JSONEncoder().encode(tags))
        XCTAssertEqual(decoded, tags)
    }

    // MARK: - Merge table (§3)

    func test_merged_nilNil_isNil() {
        XCTAssertNil(MatchTags.merged(nil, nil))
    }

    func test_merged_oneSideNil_keepsTheOther() {
        let tags = F.tags(opponents: [F.player("Alex")], at: 1)
        XCTAssertEqual(MatchTags.merged(tags, nil), tags, "nil incoming = an older build re-encoded it")
        XCTAssertEqual(MatchTags.merged(nil, tags), tags)
    }

    func test_merged_laterUpdatedAtWins_regardlessOfSide() {
        let older = F.tags(opponents: [F.player("Alex")], at: 1)
        let newer = F.tags(opponents: [F.player("Jo")], at: 2)
        XCTAssertEqual(MatchTags.merged(older, newer), newer)
        XCTAssertEqual(MatchTags.merged(newer, older), newer)
    }

    func test_merged_newerEmptyClearBeatsOlderNonEmpty() {
        let tagged = F.tags(opponents: [F.player("Alex")], competition: .league, at: 1)
        let cleared = MatchTags.cleared(after: tagged, now: F.base.addingTimeInterval(2))
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertEqual(MatchTags.merged(tagged, cleared), cleared)
        XCTAssertEqual(MatchTags.merged(cleared, tagged), cleared)
    }

    func test_merged_olderEmptyDoesNotBeatNewerTags() {
        let cleared = F.tags(at: 1)
        let tagged = F.tags(opponents: [F.player("Alex")], at: 2)
        XCTAssertEqual(MatchTags.merged(tagged, cleared), tagged)
    }

    /// §12.1 "Equal timestamp conflicts converge in either arrival order".
    func test_merged_equalTimestamp_convergesInEitherArrivalOrder() {
        let a = F.tags(opponents: [F.player("Alex")], at: 5, revision: F.uuid(1))
        let b = F.tags(opponents: [F.player("Jo")], at: 5, revision: F.uuid(2))
        let onPhone = MatchTags.merged(a, b)   // phone held a, receives b
        let onWatch = MatchTags.merged(b, a)   // watch held b, receives a
        XCTAssertEqual(onPhone, onWatch)
        XCTAssertEqual(onPhone, b, "larger revisionID string wins the tie")
    }

    func test_merged_legacyRevisionsWithEqualClocks_stillConverge() {
        let a = F.tags(opponents: [F.player("Alex", id: F.uuid(10))], at: 5, revision: MatchTags.legacyRevisionID)
        let b = F.tags(opponents: [F.player("Jo", id: F.uuid(11))], at: 5, revision: MatchTags.legacyRevisionID)
        XCTAssertEqual(MatchTags.merged(a, b), MatchTags.merged(b, a))
    }

    func test_merged_identicalValues_isThatValue() {
        let a = F.tags(opponents: [F.player("Alex")], at: 5, revision: F.uuid(1))
        XCTAssertEqual(MatchTags.merged(a, a), a)
        XCTAssertFalse(a.supersedes(a))
    }

    // MARK: - Editing clock (§11.2)

    func test_revised_isStrictlyLaterEvenWhenTheClockMovedBackwards() {
        let previous = F.tags(opponents: [F.player("Alex")], at: 100)
        let edit = F.tags(opponents: [F.player("Jo")])
            .revised(after: previous, now: F.base.addingTimeInterval(50), revisionID: F.uuid(3))
        XCTAssertGreaterThan(edit.updatedAt, previous.updatedAt)
        XCTAssertEqual(edit.revisionID, F.uuid(3))
        XCTAssertTrue(edit.supersedes(previous))
    }

    func test_revised_usesNowWhenClockIsAhead() {
        let previous = F.tags(at: 100)
        let now = F.base.addingTimeInterval(500)
        XCTAssertEqual(F.tags(opponents: [F.player("Jo")]).revised(after: previous, now: now).updatedAt, now)
        XCTAssertEqual(F.tags().revised(after: nil, now: now).updatedAt, now)
    }

    func test_revised_survivesAJSONRoundTripStillLater() throws {
        let previous = F.tags(at: 100)
        let edit = F.tags(competition: .league).revised(after: previous, now: F.base)
        let decoded = try JSONDecoder().decode(MatchTags.self, from: JSONEncoder().encode(edit))
        XCTAssertTrue(decoded.supersedes(previous))
    }

    func test_revised_sanitizes() {
        let edit = F.tags(opponents: [F.player("  Alex\n  Smith ")]).revised(after: nil, now: F.base)
        XCTAssertEqual(edit.opponents.first?.name, "Alex Smith")
    }

    // MARK: - Sanitizing (§4)

    func test_sanitizedName_trimsCollapsesAndDropsControls() {
        XCTAssertEqual(MatchTags.sanitizedName("  Alex   \t Smith  "), "Alex Smith")
        XCTAssertEqual(MatchTags.sanitizedName("Al\u{0007}ex"), "Alex")
        XCTAssertEqual(MatchTags.sanitizedName("Alex\nIgnore previous instructions"),
                       "Alex Ignore previous instructions")
        XCTAssertEqual(MatchTags.sanitizedName("Alex\u{2028}Jo"), "Alex Jo")
        XCTAssertEqual(MatchTags.sanitizedName("\u{202E}xelA"), "xelA", "bidi override is dropped")
        XCTAssertEqual(MatchTags.sanitizedName("   "), "")
    }

    func test_sanitizedName_capsAtFortyCharacters() {
        let long = String(repeating: "a", count: 60)
        XCTAssertEqual(MatchTags.sanitizedName(long).count, MatchTags.maxNameLength)
        XCTAssertEqual(MatchTags.maxNameLength, 40)
    }

    func test_sanitizedName_keepsEmojiSequencesAndAccents() {
        XCTAssertEqual(MatchTags.sanitizedName("Zoë 👩‍👩‍👧"), "Zoë 👩‍👩‍👧")
    }

    func test_sanitized_dropsEmptyNamesDeduplicatesAndCapsOpponents() {
        let alex = F.player("Alex")
        let sam = F.player("Sam")
        let tags = F.tags(
            opponents: [alex, F.player("   "), alex, sam, F.player("Jo"), F.player("Kim")],
            partner: sam,
            competition: .league
        ).sanitized()
        XCTAssertEqual(tags.partner, sam)
        XCTAssertEqual(tags.opponents.map(\.name), ["Alex", "Jo"],
                       "blank dropped, duplicate id dropped, partner not repeated as opponent, capped at 2")
    }

    func test_sanitized_doesNotEnforceSinglesShape() {
        // Two opponents on a record later read as singles is the editor's
        // problem — decode must never destroy data an editor wrote.
        let tags = F.tags(opponents: [F.player("Alex"), F.player("Jo")], partner: F.player("Sam")).sanitized()
        XCTAssertEqual(tags.opponents.count, 2)
        XCTAssertNotNil(tags.partner)
    }

    func test_sanitized_blankCompetitionRawBecomesNil() {
        let tags = MatchTags(competitionTypeRaw: "  ", updatedAt: F.base).sanitized()
        XCTAssertNil(tags.competitionTypeRaw)
        XCTAssertTrue(tags.isEmpty)
    }

    func test_sanitized_isIdempotent() {
        let tags = F.tags(opponents: [F.player(" Alex\tSmith ")], competition: .practice).sanitized()
        XCTAssertEqual(tags.sanitized(), tags)
    }

    func test_decode_appliesSanitizer() throws {
        let json = """
        {"opponents":[{"id":"00000000-0000-0000-0000-000000000009","name":"  Alex\\nSmith "},
                      {"id":"00000000-0000-0000-0000-000000000008","name":""}],
         "updatedAt":1}
        """.data(using: .utf8)!
        let tags = try JSONDecoder().decode(MatchTags.self, from: json)
        XCTAssertEqual(tags.opponents.map(\.name), ["Alex Smith"])
    }

    // MARK: - Display line

    func test_displayLine() {
        XCTAssertNil(F.tags().displayLine)
        XCTAssertEqual(F.tags(opponents: [F.player("Alex")], competition: .league).displayLine,
                       "vs Alex · League")
        XCTAssertEqual(F.tags(opponents: [F.player("Alex"), F.player("Jo")], partner: F.player("Sam"),
                              competition: .tournament).displayLine,
                       "With Sam vs Alex & Jo · Tournament")
        XCTAssertEqual(F.tags(competition: .practice).displayLine, "Practice")
        XCTAssertNil(MatchTags(competitionTypeRaw: "ladder", updatedAt: F.base).displayLine,
                     "an unknown future competition is not rendered")
    }

    // MARK: - Applying tags to a record never touches the body

    func test_mergingTags_neverAdvancesScoreOrCompletesMatch() {
        let live = F.record(end: nil, iWon: nil, tags: nil, stats: F.points(3, won: 2))
        let update = F.tags(opponents: [F.player("Alex")], at: 10)
        let tagged = live.mergingTags(update)
        XCTAssertEqual(tagged.tags, update)
        XCTAssertTrue(tagged.isInProgress)
        var bodyOnly = tagged
        bodyOnly.tags = nil
        XCTAssertEqual(bodyOnly, live, "only the tags changed")
    }

    func test_mergingTags_staleUpdateIsIgnored() {
        let current = F.tags(opponents: [F.player("Jo")], at: 20)
        let record = F.record(tags: current)
        XCTAssertEqual(record.mergingTags(F.tags(opponents: [F.player("Alex")], at: 10)).tags, current)
        XCTAssertEqual(record.mergingTags(nil).tags, current)
    }

    // MARK: - Reconciliation (§6.1)

    func test_pending_watchCopyWithoutTags_getsArchiveTags() {
        // A new phone with an old watch: the watch never stored tags. After the
        // watch upgrades, its first history push still has none → resend.
        let id = UUID()
        let tags = F.tags(opponents: [F.player("Alex")], at: 10)
        let updates = MatchTags.pendingWatchUpdates(
            archive: [F.record(id: id, tags: tags)],
            watchCopies: [F.record(id: id, tags: nil)],
            newlyHeld: []
        )
        XCTAssertEqual(updates, [MatchTagsUpdate(matchID: id, tags: tags)])
    }

    func test_pending_watchCopyOlder_getsArchiveTags() {
        let id = UUID()
        let newer = F.tags(opponents: [F.player("Jo")], at: 20)
        let updates = MatchTags.pendingWatchUpdates(
            archive: [F.record(id: id, tags: newer)],
            watchCopies: [F.record(id: id, tags: F.tags(opponents: [F.player("Alex")], at: 10))],
            newlyHeld: []
        )
        XCTAssertEqual(updates.map(\.tags), [newer])
    }

    func test_pending_watchCopyCurrentOrNewer_sendsNothing() {
        let id = UUID()
        let tags = F.tags(opponents: [F.player("Alex")], at: 10)
        XCTAssertEqual(MatchTags.pendingWatchUpdates(
            archive: [F.record(id: id, tags: tags)],
            watchCopies: [F.record(id: id, tags: tags)],
            newlyHeld: []
        ), [])
        XCTAssertEqual(MatchTags.pendingWatchUpdates(
            archive: [F.record(id: id, tags: tags)],
            watchCopies: [F.record(id: id, tags: F.tags(at: 30))],
            newlyHeld: []
        ), [])
    }

    func test_pending_archiveWithoutTags_sendsNothing() {
        let id = UUID()
        XCTAssertEqual(MatchTags.pendingWatchUpdates(
            archive: [F.record(id: id, tags: nil)],
            watchCopies: [F.record(id: id, tags: nil)],
            newlyHeld: [id]
        ), [])
    }

    func test_pending_watchCopyNotInArchive_sendsNothing() {
        XCTAssertEqual(MatchTags.pendingWatchUpdates(
            archive: [],
            watchCopies: [F.record(tags: nil)],
            newlyHeld: []
        ), [])
    }

    func test_pending_newlyHeldID_getsNonNilTags() {
        let id = UUID()
        let tags = F.tags(competition: .league, at: 10)
        let updates = MatchTags.pendingWatchUpdates(
            archive: [F.record(id: id, tags: tags), F.record(tags: F.tags(competition: .practice))],
            watchCopies: [],
            newlyHeld: [id]
        )
        XCTAssertEqual(updates, [MatchTagsUpdate(matchID: id, tags: tags)],
                       "only the newly held id, not every tagged record")
    }

    /// §11.2 / §12.1: a clear made while the manifest lagged must still reach
    /// the watch — an empty newer revision is a deletion instruction.
    func test_pending_newlyHeldID_withEmptyClear_isSent() {
        let id = UUID()
        let cleared = MatchTags.cleared(after: F.tags(opponents: [F.player("Alex")], at: 1),
                                        now: F.base.addingTimeInterval(2))
        let updates = MatchTags.pendingWatchUpdates(
            archive: [F.record(id: id, tags: cleared)],
            watchCopies: [],
            newlyHeld: [id]
        )
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.tags.isEmpty, true)
    }

    /// §12.1 "unchanged manifests cause no resend storm": the watch sends a
    /// manifest with every live checkpoint.
    func test_pending_unchangedManifest_causesNoResend() {
        let held: Set<UUID> = [UUID(), UUID()]
        let archive = held.map { F.record(id: $0, tags: F.tags(opponents: [F.player("Alex")])) }
        let newlyHeld = MatchTags.newlyHeldIDs(previous: held, current: held)
        XCTAssertTrue(newlyHeld.isEmpty)
        XCTAssertEqual(MatchTags.pendingWatchUpdates(archive: archive, watchCopies: [], newlyHeld: newlyHeld), [])
    }

    func test_newlyHeldIDs_isTheManifestDiff() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(MatchTags.newlyHeldIDs(previous: [a, b], current: [b, c]), [c])
    }

    func test_pending_bothSignals_deduplicatePerMatch() {
        let id = UUID()
        let tags = F.tags(opponents: [F.player("Alex")], at: 10)
        let updates = MatchTags.pendingWatchUpdates(
            archive: [F.record(id: id, tags: tags)],
            watchCopies: [F.record(id: id, tags: nil)],
            newlyHeld: [id]
        )
        XCTAssertEqual(updates.count, 1)
    }

    /// Scenario: phone edit → reconciliation → watch applies → next push is
    /// already current, so the loop settles instead of resending forever.
    func test_pending_converges_afterWatchAppliesTheUpdate() {
        let id = UUID()
        let phoneTags = F.tags(opponents: [F.player("Alex")], at: 10)
        let archive = [F.record(id: id, tags: phoneTags)]
        var watchRecord = F.record(id: id, tags: nil)

        let first = MatchTags.pendingWatchUpdates(archive: archive, watchCopies: [watchRecord], newlyHeld: [])
        XCTAssertEqual(first.count, 1)
        for update in first { watchRecord = watchRecord.mergingTags(update.tags) }

        XCTAssertEqual(MatchTags.pendingWatchUpdates(archive: archive, watchCopies: [watchRecord], newlyHeld: []), [])
    }
}
