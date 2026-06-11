// MatchSyncPayloadBuilder.swift — pure construction of WatchConnectivity payloads.
//
// Both `MatchSyncTransport` and the per-platform sync delegates send `[String: Any]`
// dictionaries over WCSession. They used to assemble those dictionaries inline,
// which (a) duplicated the stringly-typed `MatchSyncKey` wiring across sites and
// (b) lived inside `#if canImport(WatchConnectivity)` (the transport) or the app
// targets — neither reachable from the macOS package tests. Centralising the
// construction here, in pure Foundation, gives a single source of truth for the
// wire format and makes every payload shape round-trippable against
// `SyncIncomingPayload.decode` in unit tests.
import Foundation

public enum MatchSyncPayloadBuilder {

    // MARK: - Records

    /// Assembles a live checkpoint payload from an already-encoded record. Kept
    /// separate from `checkpoint(record:…)` so the transport can reuse the `Data`
    /// it encoded up front (preserving its encode-error handling) while tests and
    /// other callers use the throwing convenience below.
    ///
    /// `completedClearsActive == true` finalises the match (clear the peer's active
    /// pointer); otherwise the payload carries the active match id.
    public static func checkpointPayload(
        recordData: Data,
        recordID: UUID,
        completedClearsActive: Bool,
        announcement: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [MatchSyncKey.singleMatch: recordData]
        if completedClearsActive {
            payload[MatchSyncKey.clearActiveMatch] = true
        } else {
            payload[MatchSyncKey.activeMatchID] = recordID.uuidString
        }
        if let announcement { payload[MatchSyncKey.liveAnnouncement] = announcement }
        return payload
    }

    /// Encodes `record` and assembles its checkpoint payload.
    public static func checkpoint(
        record: MatchRecord,
        completedClearsActive: Bool,
        announcement: String?
    ) throws -> [String: Any] {
        checkpointPayload(
            recordData: try MatchSyncMessage.encode(record),
            recordID: record.id,
            completedClearsActive: completedClearsActive,
            announcement: announcement
        )
    }

    /// One-shot reliable single-record payload from already-encoded data.
    public static func singleRecordPayload(data: Data) -> [String: Any] {
        [MatchSyncKey.singleMatch: data]
    }

    /// One-shot reliable single-record payload (manual-entry recovery).
    public static func singleRecord(_ record: MatchRecord) throws -> [String: Any] {
        singleRecordPayload(data: try MatchSyncMessage.encode(record))
    }

    /// Full-history payload from already-encoded data.
    public static func historyPayload(data: Data) -> [String: Any] {
        [MatchSyncKey.matchHistory: data]
    }

    /// Full-history payload.
    public static func history(_ records: [MatchRecord]) throws -> [String: Any] {
        historyPayload(data: try MatchSyncMessage.encode(records))
    }

    // MARK: - Control

    /// Watch → phone manifest of the match IDs the watch currently holds.
    public static func watchManifest(_ ids: [UUID]) throws -> [String: Any] {
        let data = try JSONEncoder().encode(ids.map(\.uuidString))
        return [MatchSyncKey.watchManifest: data]
    }

    /// Phone → watch command to delete a single match from the watch only.
    public static func deleteMatchOnWatch(_ id: UUID) -> [String: Any] {
        [
            MatchSyncKey.deleteMatchOnWatch: true,
            MatchSyncKey.deleteMatchID: id.uuidString
        ]
    }

    /// Phone → watch request for the watch's full history.
    public static func requestFullHistory() -> [String: Any] {
        [MatchSyncKey.requestFullHistory: true]
    }
}
