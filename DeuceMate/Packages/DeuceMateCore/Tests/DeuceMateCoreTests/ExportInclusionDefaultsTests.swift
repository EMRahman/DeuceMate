// ExportInclusionDefaultsTests.swift — the export defaults are a privacy
// decision, and the remembered choices live under persisted UserDefaults keys.
// Pin both so a change is deliberate, not a refactor side effect.
import XCTest
@testable import DeuceMateCore

final class ExportInclusionDefaultsTests: XCTestCase {

    func test_defaults_namesAndPlayingNotesOn_privateNotesOff() {
        XCTAssertTrue(ExportInclusionDefaults.includePlayerNames)
        XCTAssertTrue(ExportInclusionDefaults.includePlayingNotes)
        XCTAssertFalse(ExportInclusionDefaults.includePrivateNotes,
                       "Private notes must stay a per-export opt-in")
    }

    /// Renaming a key silently resets every player's remembered choice.
    func test_keys_arePersistedIdentifiers() {
        XCTAssertEqual(ExportInclusionDefaults.includePlayerNamesKey, "exportIncludePlayerNames")
        XCTAssertEqual(ExportInclusionDefaults.includePlayingNotesKey, "gamePlanIncludePlayingNotes")
    }

    /// iPhone-local: neither key may double as a wire key, or the Watch sync
    /// handlers would start treating it as a synced setting.
    func test_keys_areNotSyncedSettingKeys() {
        let synced = [
            MatchSyncKey.playerName,
            MatchSyncKey.announcedName,
            MatchSyncKey.statsTrackingEnabled,
            MatchSyncKey.swipeHapticsEnabled
        ]
        for key in [ExportInclusionDefaults.includePlayerNamesKey,
                    ExportInclusionDefaults.includePlayingNotesKey] {
            XCTAssertFalse(synced.contains(key), key)
        }
        XCTAssertNotEqual(ExportInclusionDefaults.includePlayerNamesKey,
                          ExportInclusionDefaults.includePlayingNotesKey)
    }

    /// A fresh install (nothing stored) reads the defaults through the same
    /// `object(forKey:) as? Bool ?? default` rule `@AppStorage` applies.
    func test_freshDefaults_readTheDefaults_andAStoredChoiceWins() throws {
        let suite = "ExportInclusionDefaultsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        func names() -> Bool {
            defaults.object(forKey: ExportInclusionDefaults.includePlayerNamesKey) as? Bool
                ?? ExportInclusionDefaults.includePlayerNames
        }
        XCTAssertTrue(names())
        defaults.set(false, forKey: ExportInclusionDefaults.includePlayerNamesKey)
        XCTAssertFalse(names(), "A remembered OFF survives")
    }
}
