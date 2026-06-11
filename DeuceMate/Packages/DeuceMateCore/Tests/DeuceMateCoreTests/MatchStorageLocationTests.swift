// MatchStorageLocationTests.swift — coverage for the storage-location resolver.
import XCTest
@testable import DeuceMateCore

final class MatchStorageLocationTests: XCTestCase {

    func test_location_onBothDevices_isBoth() {
        let id = UUID()
        let location = MatchStorageResolver.location(matchID: id, onPhone: true, watchIDs: [id])
        XCTAssertEqual(location, .both)
    }

    func test_location_phoneOnly_whenNotInWatchManifest() {
        let id = UUID()
        let location = MatchStorageResolver.location(matchID: id, onPhone: true, watchIDs: [UUID()])
        XCTAssertEqual(location, .phoneOnly)
    }

    func test_location_watchOnly_whenNotOnPhone() {
        let id = UUID()
        let location = MatchStorageResolver.location(matchID: id, onPhone: false, watchIDs: [id])
        XCTAssertEqual(location, .watchOnly)
    }

    func test_location_onNeither_fallsBackToPhoneOnly() {
        // Defensive: a row only ever renders for a match the phone holds, so this
        // branch shouldn't occur in practice, but the resolver must stay total.
        let location = MatchStorageResolver.location(matchID: UUID(), onPhone: false, watchIDs: [])
        XCTAssertEqual(location, .phoneOnly)
    }

    func test_watchOnlyIDs_isSetDifference() {
        let shared = UUID()
        let watchExtra = UUID()
        let phoneExtra = UUID()
        let watchOnly = MatchStorageResolver.watchOnlyIDs(
            phoneIDs: [shared, phoneExtra],
            watchIDs: [shared, watchExtra]
        )
        XCTAssertEqual(watchOnly, [watchExtra])
    }

    func test_watchOnlyIDs_emptyWhenWatchSubsetOfPhone() {
        let a = UUID(), b = UUID()
        let watchOnly = MatchStorageResolver.watchOnlyIDs(phoneIDs: [a, b], watchIDs: [a])
        XCTAssertTrue(watchOnly.isEmpty)
    }

    // MARK: - Empty-set edge cases

    func test_location_emptyWatchManifest_isPhoneOnly() {
        let id = UUID()
        XCTAssertEqual(
            MatchStorageResolver.location(matchID: id, onPhone: true, watchIDs: []),
            .phoneOnly
        )
    }

    func test_watchOnlyIDs_emptyWatchIDs_isEmpty() {
        let watchOnly = MatchStorageResolver.watchOnlyIDs(phoneIDs: [UUID(), UUID()], watchIDs: [])
        XCTAssertTrue(watchOnly.isEmpty)
    }

    func test_watchOnlyIDs_emptyPhoneIDs_returnsAllWatchIDs() {
        let a = UUID(), b = UUID()
        let watchOnly = MatchStorageResolver.watchOnlyIDs(phoneIDs: [], watchIDs: [a, b])
        XCTAssertEqual(watchOnly, [a, b])
    }

    func test_watchOnlyIDs_bothEmpty_isEmpty() {
        XCTAssertTrue(MatchStorageResolver.watchOnlyIDs(phoneIDs: [], watchIDs: []).isEmpty)
    }
}
