// ArchiveDiagnosticsTests.swift — damaged-copy names, the screen's status and
// the Archive Diagnostics report (ARCHIVE_DERISK_PLAN.md §5).
import CryptoKit
import XCTest
@testable import DeuceMateCore

final class ArchiveDiagnosticsTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 785_585_700) // 2025-11-23T10:15:00Z

    // MARK: - Names and status

    func test_damagedCopyName_roundTrips() throws {
        let name = ArchiveDiagnostics.damagedCopyName(for: "matchHistory.json", at: date)
        XCTAssertEqual(name, "matchHistory.json.corrupt-20251123T101500")
        let parsed = try XCTUnwrap(ArchiveDiagnostics.parseDamagedCopy(name))
        XCTAssertEqual(parsed, .init(originalFile: "matchHistory.json", isDated: true, movedAt: date))
        XCTAssertEqual(ArchiveDiagnostics.parseDamagedCopy("forgottenPlayers.json.corrupt"),
                       .init(originalFile: "forgottenPlayers.json", isDated: false, movedAt: nil))
        XCTAssertEqual(ArchiveDiagnostics.parseDamagedCopy("healthData.json.corrupt-20251123T101500")?.isBackedUpFile, false)
        XCTAssertNil(ArchiveDiagnostics.parseDamagedCopy("matchHistory.json"))
        XCTAssertNil(ArchiveDiagnostics.parseDamagedCopy("archiveInitialized.json"))
    }

    func test_status_fromArchiveFileNames() {
        let status = ArchiveDiagnostics.status(forArchiveFileNames:)
        XCTAssertEqual(status(["matchHistory.json", "healthData.json"]), .noProblems)
        // A damaged Health sidecar alone needs nothing from the user.
        XCTAssertEqual(status(["healthData.json.corrupt-20251123T101500", "healthData.json.corrupt"]), .noProblems)
        // A legacy (undated) copy needs attention but never pauses iCloud.
        let legacy = status(["deletedMatchIDs.json.corrupt"])
        XCTAssertEqual(legacy, .legacyOnly)
        XCTAssertTrue(legacy.needsAttention)
        XCTAssertFalse(legacy.pausesICloud)
        XCTAssertEqual(legacy.title, "An earlier version couldn't open some match data")
        // Any dated copy of a backed-up file wins.
        let damaged = status(["matchHistory.json.corrupt", "forgottenPlayers.json.corrupt-20251123T101500"])
        XCTAssertEqual(damaged, .damaged)
        XCTAssertTrue(damaged.pausesICloud)
        XCTAssertEqual(status([]).title, "No problems found")
    }

    func test_readablePath_formatsIndicesAndKeys() throws {
        let json = #"[{"a":1},{"a":1,"b":[0,"x"]}]"#
        struct Row: Decodable { let a: Int; let b: [Int]? }
        do {
            _ = try JSONDecoder().decode([Row].self, from: Data(json.utf8))
            XCTFail("expected a decoding error")
        } catch let DecodingError.typeMismatch(_, context) {
            XCTAssertEqual(ArchiveDiagnostics.readablePath(context.codingPath), "[1].b[1]")
        }
    }

    // MARK: - Report

    /// A history whose third point has an ending shot this build doesn't know,
    /// on a match tagged with a name and playing notes.
    private func damagedHistory() throws -> Data {
        let tags = MatchTags(
            opponents: [TaggedPlayer(name: "Pat Privateperson", playingNotes: "Secret scouting note")],
            updatedAt: date
        )
        let record = MatchRecord(
            startTime: date, setScores: [],
            stats: [EndingShot.serve, .serve, .rally].map { PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, endingShot: $0) },
            tags: tags
        )
        let json = String(decoding: try JSONEncoder().encode([record]), as: UTF8.self)
        return Data(json.replacingOccurrences(of: #""endingShot":"rally""#, with: #""endingShot":"dropShot""#).utf8)
    }

    private func report(copies: [ArchiveDiagnostics.DamagedCopy], iCloudFiles: [ArchiveDiagnostics.ICloudFile]? = []) -> ArchiveDiagnostics.Report {
        ArchiveDiagnostics.Report(
            appVersion: "1.5.0", appBuild: "42", osVersion: "iOS 27.1", date: date,
            iCloudStatus: copies.isEmpty ? .backedUp : .pausedDamagedArchive,
            localFiles: [
                .init(folder: "MatchArchive", name: "matchHistory.json", size: 120, modified: date),
                .init(folder: "MatchArchive", name: "matchHistory.json.corrupt-20251123T101500", size: 900, modified: nil),
                .init(folder: "Documents", name: "deletedMatchIDs.json", size: nil, modified: date)
            ],
            iCloudFiles: iCloudFiles,
            damagedCopies: copies
        )
    }

    func test_report_damagedCopy_holdsPathHashAndValues_neverNamesOrNotes() throws {
        let data = try damagedHistory()
        let copy = try XCTUnwrap(ArchiveDiagnostics.DamagedCopy(name: "matchHistory.json.corrupt-20251123T101500", data: data))
        let sidecar = try XCTUnwrap(ArchiveDiagnostics.DamagedCopy(name: "healthData.json.corrupt-20251123T101500", data: Data("{".utf8)))
        let report = report(copies: [copy, sidecar])
        let markdown = report.markdown

        XCTAssertEqual(report.status, .damaged)
        XCTAssertTrue(markdown.contains("`dataCorrupted` at `[0].stats[2].endingShot`"), markdown)
        XCTAssertTrue(markdown.contains("dropShot"))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(markdown.contains("- SHA-256: \(hash)"))
        XCTAssertTrue(markdown.contains("- Moved aside: 2025-11-23T10:15:00Z"))
        XCTAssertTrue(markdown.contains("- EndingShot: serve, return, servePlusOne, rally"))
        XCTAssertTrue(markdown.contains("- MatchFormat: standard, bestOf3FullFinalSet, superTiebreak, perpetualSuperTiebreak, quick4Games, shortSets, fast4, perpetualPoints"))
        XCTAssertTrue(markdown.contains("## 4. Damaged copies"))
        XCTAssertTrue(markdown.contains("## 6. Instructions for a coding agent"))
        XCTAssertTrue(markdown.contains("Support: \(ArchiveDiagnostics.supportAddress)"))
        XCTAssertFalse(markdown.contains("Pat Privateperson"))
        XCTAssertFalse(markdown.contains("Secret scouting note"))
        // The Health sidecar's copy is reported but never attached.
        XCTAssertTrue(markdown.contains("### healthData.json.corrupt-20251123T101500"))
        XCTAssertEqual(report.attachableCopyNames, ["matchHistory.json.corrupt-20251123T101500"])
        XCTAssertEqual(report.filename, "DeuceMate-archive-report-2025-11-23.md")
    }

    func test_report_copyThisBuildCanRead_saysSo() throws {
        let copy = try XCTUnwrap(ArchiveDiagnostics.DamagedCopy(name: "deletedMatchIDs.json.corrupt", data: Data("[]".utf8)))
        XCTAssertEqual(copy.decode, .readable)
        let markdown = report(copies: [copy]).markdown
        XCTAssertTrue(markdown.contains("**this build can read this file.**"))
        XCTAssertTrue(markdown.contains("- Moved aside: unknown (kept by an earlier version)"))
        XCTAssertEqual(report(copies: [copy]).status, .legacyOnly)
    }

    func test_report_noDamagedCopy_leavesOutDamageAndRepairSections() {
        let markdown = report(copies: []).markdown
        XCTAssertTrue(markdown.contains("No damaged copies of match data."))
        XCTAssertFalse(markdown.contains("## 4."))
        XCTAssertFalse(markdown.contains("## 6."))
        XCTAssertTrue(markdown.contains("## 5. Stored values this build accepts"))
    }

    func test_report_filesTables() {
        let iCloud: [ArchiveDiagnostics.ICloudFile] = [
            .init(name: "matchHistory.json", size: 120, modified: date,
                  upload: .init(isUploaded: true, isUploading: false, errorDomain: nil, errorCode: nil), isDownloaded: true),
            .init(name: "deletedMatchIDs.json", size: nil, modified: nil,
                  upload: .init(isUploaded: false, isUploading: true, errorDomain: nil, errorCode: nil), isDownloaded: false),
            .init(name: "forgottenPlayers.json", size: 30, modified: date,
                  upload: .init(isUploaded: false, isUploading: false, errorDomain: nil, errorCode: nil), isDownloaded: nil),
            .init(name: "archiveInitialized.json", size: 4, modified: date,
                  upload: .init(isUploaded: false, isUploading: false, errorDomain: "NSCocoaErrorDomain", errorCode: 4355), isDownloaded: true),
            .init(name: "other.json", size: 1, modified: date,
                  upload: .init(isUploaded: nil, isUploading: nil, errorDomain: nil, errorCode: nil), isDownloaded: nil)
        ]
        let markdown = report(copies: [], iCloudFiles: iCloud).markdown
        XCTAssertTrue(markdown.contains("| MatchArchive | matchHistory.json | 120 | 2025-11-23T10:15:00Z | no |"))
        XCTAssertTrue(markdown.contains("| MatchArchive | matchHistory.json.corrupt-20251123T101500 | 900 | unknown | yes |"))
        XCTAssertTrue(markdown.contains("| Documents | deletedMatchIDs.json | unknown | 2025-11-23T10:15:00Z | no |"))
        XCTAssertTrue(markdown.contains("iCloud backup: Backed up to iCloud"))
        XCTAssertTrue(markdown.contains("| matchHistory.json | 120 | 2025-11-23T10:15:00Z | Uploaded | yes |"))
        XCTAssertTrue(markdown.contains("| deletedMatchIDs.json | unknown | unknown | Uploading | no |"))
        XCTAssertTrue(markdown.contains("| forgottenPlayers.json | 30 | 2025-11-23T10:15:00Z | Waiting to upload | unknown |"))
        XCTAssertTrue(markdown.contains("| Upload failed (NSCocoaErrorDomain 4355) |"))
        XCTAssertTrue(markdown.contains("| other.json | 1 | 2025-11-23T10:15:00Z | unknown | unknown |"))

        XCTAssertTrue(report(copies: [], iCloudFiles: nil).markdown
            .contains("iCloud is unavailable on this iPhone, so its files can't be listed."))
        XCTAssertEqual(ArchiveDiagnostics.ICloudFile.displayName(forEntry: ".matchHistory.json.icloud"), "matchHistory.json")
        XCTAssertEqual(ArchiveDiagnostics.ICloudFile.displayName(forEntry: "matchHistory.json"), "matchHistory.json")
    }
}
