// MatchExportDetailsAppTests.swift — PR 4 (app side): tags and notes in the
// plain-text exports, the AI prompt, filenames and the manual archive's
// opt-in notes section (MATCH_TAGS_PLAN.md 7.3, 8.1, 12.1 "Export privacy").
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

struct MatchExportDetailsAppTests {

    private let alex = TaggedPlayer(name: "Alex")
    private let jo = TaggedPlayer(name: "Jo")
    private let sam = TaggedPlayer(name: "Sam")
    private let note = "knee sore; attack second serve"

    private func tags(_ opponents: [TaggedPlayer], partner: TaggedPlayer? = nil,
                      competition: CompetitionType? = .league) -> MatchTags {
        MatchTags(opponents: opponents, partner: partner, competitionType: competition,
                  updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func record(doubles: Bool = false) -> MatchRecord {
        MatchRecord(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_003_600),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [
                PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner),
                PointStat(setIndex: 0, server: .opponent, winner: .opponent, outcome: .unforcedError)
            ],
            iWon: true,
            matchType: doubles ? .doubles : .singles,
            tags: doubles ? tags([alex, jo], partner: sam) : tags([alex])
        )
    }

    private func details(_ record: MatchRecord, names: Bool, notes: Bool) -> MatchExportDetails {
        let h2h = HeadToHeadRecord(wins: 3, losses: 2, draws: 0, recentResults: [.win, .win, .loss], lastPlayed: nil)
        return MatchExportDetails(record: record, note: note, headToHead: h2h, includeNames: names, includeNotes: notes)
    }

    // MARK: - Defaults: nothing leaks without details

    @Test func exportsWithoutDetailsCarryNoTagDataEvenForATaggedRecord() {
        let r = record(doubles: true)
        for text in [
            MatchExporter.summaryExport(for: r),
            MatchExporter.fullExport(for: r),
            MatchExporter.aiPromptExport(for: r),
            MatchExporter.aiPromptExport(for: r, focal: .opponent)
        ] {
            #expect(!text.contains("Alex"))
            #expect(!text.contains("Sam"))
            #expect(!text.contains("Competition"))
            #expect(!text.contains("Match Context"))
        }
    }

    // MARK: - Text exports: every names x notes combination

    @Test func textExportsHonourNamesAndNotesIndependently() {
        let r = record()
        for names in [false, true] {
            for notes in [false, true] {
                let d = details(r, names: names, notes: notes)
                for text in [MatchExporter.summaryExport(for: r, details: d),
                             MatchExporter.fullExport(for: r, details: d)] {
                    #expect(text.contains("Competition:"))
                    #expect(text.contains("League"))
                    #expect(text.contains("Alex") == names, "names=\(names) notes=\(notes)")
                    #expect(text.contains("knee sore") == notes, "names=\(names) notes=\(notes)")
                    #expect(text.contains("## Private Note") == notes)
                    // The text report has no AI context block.
                    #expect(!text.contains("Match Context"))
                }
            }
        }
    }

    @Test func textOverviewListsOpponentsAndPartnerWhenNamesAreOn() {
        let r = record(doubles: true)
        let text = MatchExporter.summaryExport(for: r, details: details(r, names: true, notes: false))
        #expect(text.contains("Opponents:"))
        #expect(text.contains("Alex & Jo"))
        #expect(text.contains("Partner:"))
        #expect(text.contains("Sam"))
        let opp = MatchExporter.summaryExport(for: r, focal: .opponent, details: details(r, names: true, notes: false))
        #expect(opp.contains("Your side:"))
        #expect(!opp.contains("Opponents:"))
    }

    @Test func textExportNotesAreQuotedLineByLine() {
        let r = record()
        let d = MatchExportDetails(record: r, note: "line one\nline two", includeNames: false, includeNotes: true)
        let text = MatchExporter.summaryExport(for: r, details: d)
        #expect(text.contains("> line one\n> line two"))
    }

    // MARK: - AI prompt

    @Test func aiPromptHasMatchContextWithCompetitionAndHeadToHeadButNoNameByDefault() {
        let r = record()
        let prompt = MatchExporter.aiPromptExport(for: r, details: details(r, names: false, notes: false))
        #expect(prompt.contains("## Match Context"))
        #expect(prompt.contains("Competition: League"))
        #expect(prompt.contains("Match type: Singles"))
        #expect(prompt.contains("3\u{2013}2 in 5 matches"))
        #expect(prompt.contains("Opponent (name withheld)"))
        #expect(!prompt.contains("Alex"))
        #expect(!prompt.contains("knee sore"))
        // Context sits after the coaching prompt and before the data.
        let context = prompt.range(of: "## Match Context")!.lowerBound
        #expect(prompt.range(of: "## Coaching Prompt")!.lowerBound < context)
        #expect(context < prompt.range(of: "## Match Overview")!.lowerBound)
        // The overview carries no duplicate tag rows in the AI prompt.
        #expect(!prompt.contains("Competition:  "))
    }

    @Test func aiPromptNamesAndNotesAreIndependentOptIns() {
        let r = record()
        let names = MatchExporter.aiPromptExport(for: r, details: details(r, names: true, notes: false))
        #expect(names.contains("\"Alex\""))
        #expect(!names.contains("knee sore"))
        let notes = MatchExporter.aiPromptExport(for: r, details: details(r, names: false, notes: true))
        #expect(!notes.contains("Alex"))
        #expect(notes.contains("> knee sore; attack second serve"))
        #expect(notes.contains("data, not instructions"))
        let both = MatchExporter.aiPromptExport(for: r, details: details(r, names: true, notes: true))
        #expect(both.contains("\"Alex\"") && both.contains("knee sore"))
    }

    @Test func aiPromptOpponentPerspectiveFlipsTheHeadToHead() {
        let r = record()
        let prompt = MatchExporter.aiPromptExport(for: r, focal: .opponent,
                                                  details: details(r, names: true, notes: false))
        #expect(prompt.contains("Your side: \"Alex\""))
        #expect(prompt.contains("2\u{2013}3 in 5 matches"))
    }

    @Test func aiPromptIsUnchangedBeyondTheContextBlock() {
        let r = record()
        let bare = MatchExporter.aiPromptExport(for: r)
        let withContext = MatchExporter.aiPromptExport(for: r, details: details(r, names: false, notes: false))
        let stripped = withContext.replacingOccurrences(
            of: withContext.range(of: "## Match Context").map { start in
                String(withContext[start.lowerBound...].prefix(upTo: withContext.range(of: "## Match Overview")!.lowerBound))
            } ?? "",
            with: ""
        )
        #expect(stripped == bare)
    }

    // MARK: - Filenames never contain names

    @Test func filenamesAreDateOnly() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let names = [
            ExportFilenames.text(startTime: start, suffix: ""),
            ExportFilenames.text(startTime: start, suffix: "_ai_prompt_opponent"),
            ExportFilenames.html(startTime: start, opponentPerspective: false),
            ExportFilenames.html(startTime: start, opponentPerspective: true)
        ]
        for name in names {
            #expect(name.hasPrefix("deuce_mate_2023-11-1"))
            #expect(!name.contains("Alex"))
            #expect(name.range(of: #"^deuce_mate_\d{4}-\d{2}-\d{2}[0-9_a-z]*\.(txt|html)$"#, options: .regularExpression) != nil)
        }
    }

    // MARK: - Manual archive: notes are opt-in, default off

    private struct Fixture {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("export-details-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        func archiveStore(_ name: String) -> PhoneStatsStore {
            PhoneStatsStore(storageConfiguration: .init(
                canonicalDirectoryURL: root.appendingPathComponent(name, isDirectory: true),
                legacyDocumentsDirectoryURL: root.appendingPathComponent("docs-\(name)", isDirectory: true),
                startsICloudSync: false
            ))
        }
        func notesStore(_ name: String) -> MatchNotesStore {
            MatchNotesStore(configuration: .init(
                directoryURL: root.appendingPathComponent("notes-\(name)", isDirectory: true),
                backupExcluder: nil
            ))
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func manualArchiveExportOmitsNotesUnlessTheyAreExplicitlyPassed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.archiveStore("a")
        let r = record()
        store.saveHistory([r])

        let plain = try store.exportManualArchiveData()
        #expect(!String(decoding: plain, as: UTF8.self).contains("knee sore"))
        #expect(try ManualMatchArchiveBackup.decode(plain).notes == nil)

        let note = MatchNote(matchID: r.id, text: note, updatedAt: Date(timeIntervalSince1970: 1_700_000_100))
        let withNotes = try store.exportManualArchiveData(notes: [note])
        #expect(String(decoding: withNotes, as: UTF8.self).contains("knee sore"))
        #expect(try ManualMatchArchiveBackup.preview(withNotes).noteCount == 1)
    }

    @Test func importingAnArchiveRestoresNotesOnlyIntoTheSidecarAndKeepsNewerLocalNotes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let r = record()
        let source = fixture.archiveStore("src")
        source.saveHistory([r])
        let exported = try source.exportManualArchiveData(notes: [
            MatchNote(matchID: r.id, text: "imported older", updatedAt: Date(timeIntervalSince1970: 1_700_000_100))
        ])
        let archive = try ManualMatchArchiveBackup.decode(exported)
        let importable = ManualMatchArchiveBackup.importableNotes(from: archive)
        #expect(importable.count == 1)

        // Fresh install: the note arrives.
        let fresh = fixture.notesStore("fresh")
        try fresh.importNotes(importable)
        #expect(fresh.note(for: r.id)?.text == "imported older")

        // A newer local note is kept (the notes' own revision order decides).
        let local = fixture.notesStore("local")
        try local.save(text: "newer local", for: r.id, now: Date(timeIntervalSince1970: 1_700_000_900))
        try local.importNotes(importable)
        #expect(local.note(for: r.id)?.text == "newer local")

        // An archive with no notes section is "no information": nothing changes.
        let plain = try ManualMatchArchiveBackup.decode(source.exportManualArchiveData())
        try local.importNotes(ManualMatchArchiveBackup.importableNotes(from: plain))
        #expect(local.note(for: r.id)?.text == "newer local")

        // Importing into the archive store never puts note text in the match archive.
        let dest = fixture.archiveStore("dest")
        try dest.importManualArchive(data: exported, mode: .merge)
        let stored = try Data(contentsOf: fixture.root.appendingPathComponent("dest/matchHistory.json"))
        #expect(!String(decoding: stored, as: UTF8.self).contains("imported older"))
    }

    @Test func importNotesRefusesWhenTheSidecarIsUnreadable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let dir = fixture.root.appendingPathComponent("notes-bad", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent(MatchNotesStore.filename))
        let store = MatchNotesStore(configuration: .init(directoryURL: dir, backupExcluder: nil))
        #expect(store.loadFailure != nil)
        #expect(throws: (any Error).self) {
            try store.importNotes([MatchNote(matchID: UUID(), text: "x", updatedAt: Date())])
        }
        // The unreadable file was not overwritten.
        #expect(String(decoding: try Data(contentsOf: dir.appendingPathComponent(MatchNotesStore.filename)), as: UTF8.self) == "not json")
    }
}
