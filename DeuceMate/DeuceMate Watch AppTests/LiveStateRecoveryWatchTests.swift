//
//  LiveStateRecoveryWatchTests.swift
//  DeuceMate Watch AppTests
//
//  What happens to an in-progress match whose saved state can't be read back.
//  `loadState()`'s catch resets every field and the next point writes a fresh
//  checkpoint over the file, so unless the unreadable bytes are set aside first
//  the interrupted match is gone for good — and gone silently, which is the
//  behaviour these tests pin down.
//

import Foundation
import Combine
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

struct LiveStateRecoveryWatchTests {

    private func makeTempURL(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }

    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "live-state-recovery-test-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func makeViewModel(stateURL: URL, defaults: UserDefaults) -> ScoreViewModel {
        ScoreViewModel(
            statsStore: StatsStore(fileURL: makeTempURL("live-state-recovery-store")),
            stateFileURL: stateURL,
            userDefaults: defaults
        )
    }

    @Test func unreadableState_isSetAsideAndSurvivesTheNextSave() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let url = makeTempURL("recovery-corrupt")
        let original = Data("not valid json {{{".utf8)
        try original.write(to: url)

        let viewModel = makeViewModel(stateURL: url, defaults: defaults)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: viewModel.unreadableStateFileURL)
        }

        viewModel.loadState()

        let aside = viewModel.unreadableStateFileURL
        #expect(FileManager.default.fileExists(atPath: aside.path))
        #expect(try Data(contentsOf: aside) == original)
        // The live path is clear, so scoring starts cleanly rather than
        // re-failing on every launch.
        #expect(!FileManager.default.fileExists(atPath: url.path))

        // The point that follows a failed restore must not destroy the copy.
        viewModel.saveState()
        #expect(try Data(contentsOf: aside) == original)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unreadableState_raisesACriticalWarning() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let url = makeTempURL("recovery-warning")
        try Data("not valid json {{{".utf8).write(to: url)

        let viewModel = makeViewModel(stateURL: url, defaults: defaults)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: viewModel.unreadableStateFileURL)
        }

        viewModel.loadState()

        // Critical, not a warning: the match the user was scoring is out of the
        // app's view — losing it is the consequence, not a degraded list.
        #expect(viewModel.persistenceHealth.failure?.operation == .restoreLiveMatch)
        #expect(viewModel.persistenceHealth.warning?.severity == .critical)
    }

    @Test func absentState_isNormalAndQuarantinesNothing() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let url = makeTempURL("recovery-absent")
        let viewModel = makeViewModel(stateURL: url, defaults: defaults)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: viewModel.unreadableStateFileURL)
        }

        viewModel.loadState()

        #expect(viewModel.persistenceHealth.warning == nil)
        #expect(!FileManager.default.fileExists(atPath: viewModel.unreadableStateFileURL.path))
    }

    @Test func repeatedSaveFailures_doNotRepublishTheSameWarning() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        // A directory where the state file belongs makes every write fail, which
        // is what a persistent save failure looks like from the view model.
        let url = makeTempURL("recovery-unwritable")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = makeViewModel(stateURL: url, defaults: defaults)
        var publishCount = 0
        let cancellable = viewModel.$persistenceHealth.dropFirst().sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        viewModel.saveState()
        viewModel.saveState()
        viewModel.saveState()

        // `saveState()` runs on every point, so a persistent failure must publish
        // once — republishing would redraw the live scoreboard per point for a
        // warning that is already on screen.
        #expect(viewModel.persistenceHealth.failure?.operation == .saveLiveMatch)
        #expect(publishCount == 1)
    }
}
