// MatchNotesTests.swift — private notes sidecar codec and policy. MATCH_TAGS_PLAN.md §4.1.
import XCTest
@testable import DeuceMateCore

final class MatchNotesTests: XCTestCase {

    private typealias F = TagFixtures

    private func note(_ id: UUID, _ text: String, at offset: TimeInterval, revision: UUID = UUID()) -> MatchNote {
        MatchNote(matchID: id, text: text, updatedAt: F.base.addingTimeInterval(offset), revisionID: revision)
    }

    // MARK: - Text rules

    func test_sanitizedText_preservesParagraphsAndStripsControls() {
        XCTAssertEqual(MatchNotesPolicy.sanitizedText("Attack the 2nd serve.\r\n\r\nKnee felt ok."),
                       "Attack the 2nd serve.\n\nKnee felt ok.")
        XCTAssertEqual(MatchNotesPolicy.sanitizedText("a\u{0000}b\u{0007}c\u{202E}d"), "abcd")
        XCTAssertEqual(MatchNotesPolicy.sanitizedText("line\u{2028}next\rlast"), "line\nnext\nlast")
        XCTAssertEqual(MatchNotesPolicy.sanitizedText("tab\there"), "tab\there")
        XCTAssertEqual(MatchNotesPolicy.sanitizedText("  \n\n  "), "", "whitespace-only is a clear")
    }

    func test_sanitizedText_capsAt4000Characters() {
        XCTAssertEqual(MatchNotesPolicy.maxLength, 4_000)
        XCTAssertEqual(MatchNotesPolicy.sanitizedText(String(repeating: "x", count: 5_000)).count, 4_000)
    }

    // MARK: - Editing and merge

    func test_edit_isStrictlyLaterThanPrevious_andEmptyIsAClear() {
        let id = UUID()
        let previous = note(id, "Old", at: 100)
        let cleared = MatchNotesPolicy.edit(matchID: id, text: "   ", previous: previous,
                                            now: F.base.addingTimeInterval(10))
        XCTAssertTrue(cleared.isCleared)
        XCTAssertGreaterThan(cleared.updatedAt, previous.updatedAt, "clock moved backwards; edit still wins")
        XCTAssertEqual(MatchNotesPolicy.merged(previous, cleared), cleared)
        XCTAssertEqual(MatchNotesPolicy.merged(cleared, previous), cleared)
    }

    func test_merged_equalClock_convergesInEitherOrder() {
        let id = UUID()
        let a = note(id, "A", at: 5, revision: F.uuid(1))
        let b = note(id, "B", at: 5, revision: F.uuid(2))
        XCTAssertEqual(MatchNotesPolicy.merged(a, b), MatchNotesPolicy.merged(b, a))
        XCTAssertEqual(MatchNotesPolicy.merged(a, b), b)
        XCTAssertNil(MatchNotesPolicy.merged(nil, nil))
    }

    func test_merge_preservesUnrelatedNotes() {
        let kept = note(UUID(), "Keep me", at: 1)
        let id = UUID()
        let merged = MatchNotesPolicy.merge([note(id, "New", at: 9)], into: [kept, note(id, "Old", at: 1)])
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(kept))
        XCTAssertEqual(merged.first { $0.matchID == id }?.text, "New")
    }

    func test_merge_olderImportDoesNotOverwriteNewerLocalNote() {
        let id = UUID()
        let local = note(id, "Newer local", at: 50)
        XCTAssertEqual(MatchNotesPolicy.merge([note(id, "Old export", at: 10)], into: [local]), [local])
    }

    func test_removingNotes_forPermanentlyDeletedMatches() {
        let gone = UUID(), kept = UUID()
        let result = MatchNotesPolicy.removingNotes(for: [gone], from: [note(gone, "x", at: 1), note(kept, "y", at: 1)])
        XCTAssertEqual(result.map(\.matchID), [kept])
    }

    func test_replacePlan_keepsRetainedAndListsDiscardedNonEmptyNotes() {
        let retained = UUID(), removed = UUID(), removedClear = UUID()
        let plan = MatchNotesPolicy.replacePlan(
            notes: [note(retained, "keep", at: 1), note(removed, "lose", at: 1), note(removedClear, "", at: 1)],
            retainedMatchIDs: [retained]
        )
        XCTAssertEqual(plan.retained.map(\.matchID), [retained])
        XCTAssertEqual(plan.discarded.map(\.matchID), [removed])
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertFalse(MatchNotesPolicy.replacePlan(notes: [], retainedMatchIDs: []).requiresConfirmation)
    }

    // MARK: - Codec

    func test_codec_roundTrip_withVersionAndFormat() throws {
        let notes = [note(F.uuid(2), "Second\n\nparagraph", at: 2), note(F.uuid(1), "", at: 1)]
        let data = try MatchNotesCodec.encode(notes)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["format"] as? String, "deucemate.matchNotes")
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        let decoded = try MatchNotesCodec.decode(data)
        XCTAssertEqual(decoded.map(\.matchID), [F.uuid(1), F.uuid(2)], "sorted by match id")
        XCTAssertEqual(decoded.last?.text, "Second\n\nparagraph")
        XCTAssertEqual(decoded.first?.isCleared, true, "an explicit clear round-trips")
    }

    func test_codec_corruptOrForeignFileThrows_neverEmpty() {
        XCTAssertThrowsError(try MatchNotesCodec.decode(Data()))
        XCTAssertThrowsError(try MatchNotesCodec.decode(Data("{not json".utf8)))
        XCTAssertThrowsError(try MatchNotesCodec.decode(Data(#"{"format":"other","notes":[]}"#.utf8))) {
            XCTAssertEqual($0 as? MatchNotesCodec.CodecError, .wrongFormat("other"))
        }
        XCTAssertThrowsError(try MatchNotesCodec.decode(
            Data(#"{"format":"deucemate.matchNotes","schemaVersion":99,"notes":[]}"#.utf8))) {
            XCTAssertEqual($0 as? MatchNotesCodec.CodecError, .unsupportedSchemaVersion(99))
        }
        // One malformed entry fails the file rather than being silently dropped
        // on the next save.
        XCTAssertThrowsError(try MatchNotesCodec.decode(
            Data(#"{"format":"deucemate.matchNotes","notes":[{"text":"no id"}]}"#.utf8)))
    }

    func test_codec_decodesAdditiveDefaults() throws {
        let data = Data(#"""
        {"format":"deucemate.matchNotes",
         "notes":[{"matchID":"00000000-0000-0000-0000-000000000001","text":"hi\u0007"}]}
        """#.utf8)
        let decoded = try MatchNotesCodec.decode(data)
        XCTAssertEqual(decoded.first?.text, "hi")
        XCTAssertEqual(decoded.first?.updatedAt, .distantPast)
        XCTAssertEqual(decoded.first?.revisionID, MatchTags.legacyRevisionID)
    }

    func test_codec_duplicateEntriesCollapseToNewestRevision() throws {
        let id = F.uuid(1)
        let file = MatchNotesCodec.File(notes: [note(id, "old", at: 1), note(id, "new", at: 2)])
        let decoded = try MatchNotesCodec.decode(JSONEncoder().encode(file))
        XCTAssertEqual(decoded.map(\.text), ["new"])
    }

    // MARK: - Notes never ride on a match record

    func test_notesAreNotPartOfMatchRecordOrTags() throws {
        let record = F.record(tags: F.tags(opponents: [F.player("Alex")]))
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(record), encoding: .utf8))
        XCTAssertFalse(json.contains("\"notes\""))
        XCTAssertFalse(json.contains("\"text\""))
    }
}
