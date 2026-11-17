import XCTest
@testable import DeuceMateCore

final class PlayingNotesTests: XCTestCase {
    private typealias F = TagFixtures
    func test_sanitizedPlayingNotes_trimsCollapsesCapsAndClears() {
        XCTAssertNil(TaggedPlayer.sanitizedPlayingNotes(nil))
        XCTAssertNil(TaggedPlayer.sanitizedPlayingNotes("  \n "))
        XCTAssertEqual(TaggedPlayer.sanitizedPlayingNotes(" strong first serve;\n a lot of  pace "),
                       "strong first serve; a lot of pace")
        let long = String(repeating: "a", count: 4_001)
        XCTAssertEqual(TaggedPlayer.sanitizedPlayingNotes(long)?.count, TaggedPlayer.maxPlayingNotesLength)
    }

    func test_playingNotes_preservesFourThousandCharactersThroughCodingAndRosterEdits() throws {
        let notes = String(repeating: "🎾", count: 4_000)
        XCTAssertEqual(TaggedPlayer.maxPlayingNotesLength, 4_000)
        XCTAssertEqual(TaggedPlayer.sanitizedPlayingNotes(notes + "extra"), notes)
        let player = TaggedPlayer(name: "Alex", playingNotes: notes)
        let data = try JSONEncoder().encode(player)
        let decoded = try JSONDecoder().decode(TaggedPlayer.self, from: data)
        XCTAssertEqual(decoded.playingNotes, notes)

        let records = [F.record(tags: F.tags(opponents: [TaggedPlayer(id: player.id, name: "Alex")]))]
        let updated = PlayerRoster.updatingDetails(
            player.id, handednessRaw: nil, backhandRaw: nil, playStyleRaw: nil,
            playingNotes: notes, in: records
        )
        XCTAssertEqual(PlayerRoster.entries(from: updated.records).first?.playingNotes, notes)
    }

    func test_decodingOldPlayerJSON_hasNoNotes_andRoundTrips() throws {
        let id = UUID()
        let old = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"Alex\"}".utf8)
        let decoded = try JSONDecoder().decode(TaggedPlayer.self, from: old)
        XCTAssertNil(decoded.playingNotes)

        let withNotes = TaggedPlayer(id: id, name: "Alex", playingNotes: "no topspin backhand")
        let data = try JSONEncoder().encode(withNotes)
        XCTAssertEqual(try JSONDecoder().decode(TaggedPlayer.self, from: data).playingNotes, "no topspin backhand")
    }

    func test_updatingDetails_setsAndClearsNotes_andRenamePreservesThem() throws {
        let alex = TaggedPlayer(name: "Alex")
        let records = [F.record(tags: F.tags(opponents: [alex]))]
        let updated = PlayerRoster.updatingDetails(
            alex.id, handednessRaw: nil, backhandRaw: nil, playStyleRaw: nil,
            playingNotes: "big serve", in: records
        )
        XCTAssertEqual(PlayerRoster.entries(from: updated.records).first?.playingNotes, "big serve")
        let renamed = PlayerRoster.renaming(alex.id, to: "Ali", in: updated.records)
        XCTAssertEqual(PlayerRoster.entries(from: renamed.records).first?.playingNotes, "big serve")
        let cleared = PlayerRoster.updatingDetails(
            alex.id, handednessRaw: nil, backhandRaw: nil, playStyleRaw: nil,
            playingNotes: nil, in: renamed.records
        )
        XCTAssertNil(PlayerRoster.entries(from: cleared.records).first?.playingNotes)
    }
}
