// MatchNotesStoreTests.swift — the private notes sidecar against real files:
// save / clear / relaunch, corrupt-file refusal, write failure, and the
// backup-exclusion flags on both the file and its directory (MATCH_TAGS_PLAN.md §4.1).
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

struct MatchNotesStoreTests {
    private struct Fixture {
        let root: URL
        let directory: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("match-notes-\(UUID().uuidString)", isDirectory: true)
            directory = root.appendingPathComponent("MatchNotes", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        var fileURL: URL { directory.appendingPathComponent(MatchNotesStore.filename) }

        func makeStore(backupExcluder: ((URL) throws -> Void)? = nil) -> MatchNotesStore {
            MatchNotesStore(configuration: .init(directoryURL: directory, backupExcluder: backupExcluder))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private func isExcluded(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

    @Test func saveClearAndRelaunchPersistAndKeepParagraphs() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let matchID = UUID()
        let store = fixture.makeStore()

        try store.save(text: "Attack the second serve.\n\nKnee was fine.", for: matchID)
        #expect(fixture.makeStore().allNotes().first?.text == "Attack the second serve.\n\nKnee was fine.")

        try store.save(text: "   ", for: matchID) // whitespace-only == explicit clear
        let relaunched = fixture.makeStore()
        #expect(relaunched.allNotes().first?.isCleared == true)
        #expect(relaunched.matchIDsWithNotes().isEmpty)
    }

    @Test func everyWriteLeavesFileAndDirectoryExcludedFromBackup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()

        try store.save(text: "first", for: UUID())
        #expect(try isExcluded(fixture.fileURL))
        #expect(try isExcluded(fixture.directory))

        // An atomic replacement drops the file flag; the next write reapplies it.
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        var fileURL = fixture.fileURL
        try fileURL.setResourceValues(values)
        try store.save(text: "second", for: UUID())

        #expect(try isExcluded(fixture.fileURL))
        #expect(try isExcluded(fixture.directory))
    }

    @Test func corruptSidecarIsNeverOverwritten() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let garbage = Data("{ not a notes file".utf8)
        try garbage.write(to: fixture.fileURL)

        let store = fixture.makeStore()

        #expect(store.loadFailure != nil)
        #expect(throws: MatchNotesStore.StoreError.unreadableFile) {
            try store.save(text: "new", for: UUID())
        }
        #expect(throws: MatchNotesStore.StoreError.unreadableFile) {
            try store.removeNotes(for: [UUID()])
        }
        #expect(try Data(contentsOf: fixture.fileURL) == garbage)
    }

    @Test func newerSchemaFileIsRefusedNotTreatedAsEmpty() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let future = Data(#"{"format":"deucemate.matchNotes","schemaVersion":99,"notes":[]}"#.utf8)
        try future.write(to: fixture.fileURL)

        let store = fixture.makeStore()

        #expect(throws: MatchNotesStore.StoreError.unreadableFile) {
            try store.save(text: "new", for: UUID())
        }
        #expect(try Data(contentsOf: fixture.fileURL) == future)
    }

    @Test func exclusionFailureWritesNothing() throws {
        struct ExclusionFailure: Error {}
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore { _ in throw ExclusionFailure() }

        #expect(throws: MatchNotesStore.StoreError.backupExclusionFailed) {
            try store.save(text: "private", for: UUID())
        }
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path) == false)
        #expect(store.allNotes().isEmpty)
    }

    @Test func writeFailureSurfacesAndKeepsPreviousNotes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let matchID = UUID()
        let store = fixture.makeStore()
        try store.save(text: "kept", for: matchID)
        // Make the file path un-writable by replacing it with a directory.
        try FileManager.default.removeItem(at: fixture.fileURL)
        try FileManager.default.createDirectory(at: fixture.fileURL, withIntermediateDirectories: true)

        #expect(throws: (any Error).self) {
            try store.save(text: "replacement", for: matchID)
        }
        #expect(store.allNotes().first?.text == "kept")
    }

    @Test func deletionAndReplacePlanFollowThePolicy() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = UUID(), dropped = UUID(), deleted = UUID()
        let store = fixture.makeStore()
        try store.save(text: "kept", for: kept)
        try store.save(text: "dropped", for: dropped)
        try store.save(text: "deleted", for: deleted)

        try store.removeNotes(for: [deleted])
        #expect(store.matchIDsWithNotes() == [kept, dropped])

        let plan = store.replacePlan(retainedMatchIDs: [kept])
        #expect(plan.requiresConfirmation)
        #expect(plan.discarded.map(\.matchID) == [dropped])

        try store.applyReplace(retainedMatchIDs: [kept])
        #expect(fixture.makeStore().matchIDsWithNotes() == [kept])
    }
}
