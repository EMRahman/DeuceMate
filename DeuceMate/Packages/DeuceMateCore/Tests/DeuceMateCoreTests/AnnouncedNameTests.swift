// AnnouncedNameTests.swift — the spoken recorder name: typed value first,
// otherwise the first name of "Your name", otherwise nil (caller says "you").
import XCTest
@testable import DeuceMateCore

final class AnnouncedNameTests: XCTestCase {

    func test_firstName_takesFirstWord() {
        XCTAssertEqual(AnnouncedName.firstName(of: "John Smith"), "John")
        XCTAssertEqual(AnnouncedName.firstName(of: "  Mary  Jane Watson "), "Mary")
        XCTAssertEqual(AnnouncedName.firstName(of: "Cher"), "Cher")
    }

    func test_firstName_blankIsNil() {
        XCTAssertNil(AnnouncedName.firstName(of: ""))
        XCTAssertNil(AnnouncedName.firstName(of: "   \n"))
    }

    func test_resolve_emptyAnnouncedName_followsFirstNameOfYourName() {
        XCTAssertEqual(AnnouncedName.resolve(announcedName: "", playerName: "John Smith"), "John")
        XCTAssertEqual(AnnouncedName.resolve(announcedName: "   ", playerName: "John Smith"), "John")
    }

    func test_resolve_typedAnnouncedName_wins() {
        XCTAssertEqual(AnnouncedName.resolve(announcedName: " Johnny ", playerName: "John Smith"), "Johnny")
        XCTAssertEqual(AnnouncedName.resolve(announcedName: "JJ Smith", playerName: ""), "JJ Smith")
    }

    func test_resolve_bothBlank_isNil() {
        XCTAssertNil(AnnouncedName.resolve(announcedName: "", playerName: ""))
        XCTAssertNil(AnnouncedName.resolve(announcedName: " ", playerName: "  "))
    }

    func test_placeholder_showsDefaultOrExample() {
        XCTAssertEqual(AnnouncedName.placeholder(playerName: "John Smith"), "John")
        XCTAssertEqual(AnnouncedName.placeholder(playerName: ""), "e.g. John")
    }

    func test_wireKey_isPinned() {
        // Local UserDefaults key == wire key on both devices; a rename would
        // silently reset the stored choice (CLAUDE.md §5 trap).
        XCTAssertEqual(MatchSyncKey.announcedName, "announcedName")
    }

    func test_decode_announcedName() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.announcedName: "John"])
        XCTAssertEqual(events, [.announcedName("John")])
    }

    func test_decode_announcedName_isCappedAndIgnoresNonString() {
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(
            SyncIncomingPayload.decode([MatchSyncKey.announcedName: long]),
            [.announcedName(String(repeating: "a", count: SyncIncomingPayload.maxPlayerNameLength))]
        )
        XCTAssertEqual(SyncIncomingPayload.decode([MatchSyncKey.announcedName: 42]), [])
    }
}
