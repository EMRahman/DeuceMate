// ExportStagingTests.swift — per-build staging directories for the match
// detail screen's shared export files, so an older build that finishes last
// can never overwrite (or stand in for) a newer one.
import Foundation
import Testing
@testable import DeuceMate

struct ExportStagingTests {
    private struct Fixture {
        let root: URL
        let staging: ExportStaging

        init() {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("export-staging-\(UUID().uuidString)", isDirectory: true)
            staging = ExportStaging(rootURL: root)
        }

        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private let filename = "deuce_mate_2026-11-01_1530.html"

    @Test func generationsGetDistinctPathsWithTheSameDisplayFilename() {
        let f = Fixture()
        defer { f.remove() }
        let older = f.staging.beginGeneration()
        let newer = f.staging.beginGeneration()

        let olderURL = older.url(for: filename)
        let newerURL = newer.url(for: filename)

        #expect(olderURL != newerURL)
        #expect(olderURL.lastPathComponent == filename)
        #expect(newerURL.lastPathComponent == filename)
        #expect(olderURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
                == f.root.standardizedFileURL)
        #expect(older.contains(olderURL))
        #expect(older.contains(newerURL) == false)
    }

    /// The review scenario: the newer build publishes first, the older build
    /// finishes writing afterwards. The published file must keep the newer
    /// content, and the superseded build's own files are removed.
    @Test func aSupersededBuildFinishingLastCannotOverwriteThePublishedFile() throws {
        let f = Fixture()
        defer { f.remove() }
        let older = f.staging.beginGeneration()
        let newer = f.staging.beginGeneration()

        let published = try f.staging.write(Data("score 6-4".utf8), named: filename, in: newer)
        let late = try f.staging.write(Data("score 5-4".utf8), named: filename, in: older)
        f.staging.endGeneration(older) // what the cancelled build does

        #expect(String(decoding: try Data(contentsOf: published), as: UTF8.self) == "score 6-4")
        #expect(f.exists(late) == false)
        #expect(f.exists(older.directoryURL) == false)
    }

    @Test func endingAGenerationRemovesItsDirectoryAndIsIdempotent() throws {
        let f = Fixture()
        defer { f.remove() }
        let generation = f.staging.beginGeneration()
        let mine = try f.staging.write(Data("a".utf8), named: filename, in: generation)
        let theirs = try f.staging.write(Data("b".utf8), named: "deuce_mate_2026-11-01_1530_opponent.html",
                                         in: generation)

        f.staging.endGeneration(generation)
        f.staging.endGeneration(generation)

        #expect(f.exists(mine) == false)
        #expect(f.exists(theirs) == false)
        #expect(f.exists(generation.directoryURL) == false)
    }

    /// Leftovers from builds that never ended (a killed process) are swept;
    /// a live build's files are never touched.
    @Test func sweepRemovesOnlyDirectoriesNoLiveGenerationOwns() throws {
        let f = Fixture()
        defer { f.remove() }
        let previousProcess = ExportStaging(rootURL: f.root)
        let orphan = previousProcess.beginGeneration()
        let orphanFile = try previousProcess.write(Data("old".utf8), named: filename, in: orphan)
        let ended = f.staging.beginGeneration()
        try f.staging.write(Data("x".utf8), named: filename, in: ended)
        f.staging.endGeneration(ended)
        let live = f.staging.beginGeneration()
        let liveFile = try f.staging.write(Data("current".utf8), named: filename, in: live)

        f.staging.sweepInactive()

        #expect(f.exists(orphanFile) == false)
        #expect(f.exists(liveFile))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path) == [live.id.uuidString])
    }

    @Test func waitUntilCancelledReturnsOnCancellation() async {
        let task = Task { await ExportStaging.waitUntilCancelled() }
        task.cancel()
        await task.value
        #expect(task.isCancelled)
    }
}
