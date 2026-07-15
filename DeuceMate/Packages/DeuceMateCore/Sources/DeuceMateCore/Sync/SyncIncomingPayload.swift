// SyncIncomingPayload.swift — typed decoder for inbound WatchConnectivity payloads.
//
// Both the watch and phone WCSession delegates receive `[String: Any]` dictionaries
// from three callbacks (sendMessage, sendMessage+reply, transferUserInfo) plus a
// fourth file-based path. Each delegate previously hand-decoded the same keys in
// each callback; this enum gives both sides a single typed event stream to dispatch.
//
// Pure Foundation so the package can keep building for macOS (no WatchConnectivity).
import Foundation

/// One typed event produced by decoding a raw WCSession payload.
public enum SyncIncomingEvent: Equatable {
    case history([MatchRecord])
    case singleMatch(MatchRecord)
    case activeMatchID(UUID)
    case clearActiveMatch
    /// Watch → phone manifest of the match IDs the watch currently holds. Used to
    /// badge each match's storage location on iOS.
    case watchManifest(Set<UUID>)
    /// Phone → watch command to delete a single match from the watch only.
    case deleteMatchOnWatch(UUID)
    case announcement(String)
    case requestFullHistory
    case ping
    case userBirthYear(Int)
    case userMaxHROverride(Int)
    /// The raw string value of the peer's selected `AppTheme`, sent bidirectionally.
    case selectedTheme(String)
    // Watch-only settings pushed from phone
    case statsTrackingEnabled(Bool)
    case workoutSessionEnabled(Bool)
    case checkChangeover(Bool)
    // Shared settings (bidirectional)
    case announcementsEnabled(Bool)
    /// "iPhone Input" toggle, bidirectional.
    case iPhoneInputEnabled(Bool)
    /// Player display name used in spoken announcements, bidirectional.
    case playerName(String)
    /// Scoring action issued by the iPhone spectator (one of
    /// `MatchSyncKey.scoreCommandWinMe` / `scoreCommandWinOpp` / `scoreCommandUndo`).
    /// `matchID` is the UUID of the match the iPhone displayed when the swipe
    /// happened; the watch rejects commands whose id doesn't equal its current
    /// live match identity. `nil` means the phone didn't supply one (defensive
    /// fallback — older builds, malformed payloads).
    case scoreCommand(command: String, matchID: UUID?)
    /// Watch → iPhone mirror of the pending categorization context. iPhone shows
    /// the categorization sheet when this arrives.
    case pendingPoint(PendingPointInfo)
    /// Watch → iPhone notification that the watch has advanced to phase 2 of
    /// the categorization sheet (or rolled back to phase 1 when `nil`).
    case pendingPointOutcome(PointOutcome?)
    /// Watch → iPhone signal that the pending categorization has been resolved
    /// (committed, cancelled, undone). iPhone dismisses its sheet.
    case clearPendingPoint
    /// iPhone → watch categorization action. `action` is one of
    /// `MatchSyncKey.statActionSelectOutcome` / `statActionCommitEndingShot` /
    /// `statActionCancelOutcomeSelection`. `outcome` accompanies select;
    /// `endingShot` accompanies commit-ending-shot.
    case statAction(action: String, outcome: PointOutcome?, endingShot: EndingShot?)
    /// Decoding error for one of the recognized keys. The associated key lets the
    /// delegate log/diagnose without losing the rest of the payload's events.
    case decodeError(key: String, error: Error)
}

extension SyncIncomingEvent {
    public static func == (lhs: SyncIncomingEvent, rhs: SyncIncomingEvent) -> Bool {
        switch (lhs, rhs) {
        case (.history(let a), .history(let b)): return a == b
        case (.singleMatch(let a), .singleMatch(let b)): return a == b
        case (.activeMatchID(let a), .activeMatchID(let b)): return a == b
        case (.clearActiveMatch, .clearActiveMatch): return true
        case (.watchManifest(let a), .watchManifest(let b)): return a == b
        case (.deleteMatchOnWatch(let a), .deleteMatchOnWatch(let b)): return a == b
        case (.announcement(let a), .announcement(let b)): return a == b
        case (.requestFullHistory, .requestFullHistory): return true
        case (.ping, .ping): return true
        case (.userBirthYear(let a), .userBirthYear(let b)): return a == b
        case (.userMaxHROverride(let a), .userMaxHROverride(let b)): return a == b
        case (.selectedTheme(let a), .selectedTheme(let b)): return a == b
        case (.statsTrackingEnabled(let a), .statsTrackingEnabled(let b)): return a == b
        case (.workoutSessionEnabled(let a), .workoutSessionEnabled(let b)): return a == b
        case (.checkChangeover(let a), .checkChangeover(let b)): return a == b
        case (.announcementsEnabled(let a), .announcementsEnabled(let b)): return a == b
        case (.iPhoneInputEnabled(let a), .iPhoneInputEnabled(let b)): return a == b
        case (.playerName(let a), .playerName(let b)): return a == b
        case (.scoreCommand(let ca, let ma), .scoreCommand(let cb, let mb)): return ca == cb && ma == mb
        case (.pendingPoint(let a), .pendingPoint(let b)): return a == b
        case (.pendingPointOutcome(let a), .pendingPointOutcome(let b)): return a == b
        case (.clearPendingPoint, .clearPendingPoint): return true
        case (.statAction(let aa, let oa, let ea), .statAction(let ab, let ob, let eb)):
            return aa == ab && oa == ob && ea == eb
        case (.decodeError(let ka, _), .decodeError(let kb, _)): return ka == kb
        default: return false
        }
    }
}

public enum SyncIncomingPayload {
    // MARK: - Input bounds
    //
    // WatchConnectivity peers are the user's own Apple-paired devices, so these
    // bounds defend against corrupt state and buggy/old peers rather than a
    // network attacker. They keep a single malformed field from exhausting
    // resources (TTS lockup, oversized Set allocation, UserDefaults bloat) or
    // persisting nonsense numeric settings.

    /// Player display name is interpolated into spoken announcements and persisted.
    /// Truncate rather than drop so an oversized value degrades gracefully.
    static let maxPlayerNameLength = 128
    /// Spoken announcement text. An over-long utterance can wedge the TTS engine,
    /// so a too-long string is dropped entirely.
    static let maxAnnouncementLength = 2_000
    /// Watch → phone id manifest. The watch hard-caps its rolling history at
    /// `WatchHistory.cap` (25); this is a loose phone-side ceiling so a corrupt
    /// blob can't expand into a giant Set.
    static let maxManifestEntries = 200
    /// Plausible human heart-rate ceiling (bpm) for max-HR settings.
    static let maxHeartRate = 300
    /// Plausible birth-year window for the age-derived max-HR default.
    static let birthYearRange = 1900...2100

    /// Decodes every recognised key in the payload into a typed event. Order is
    /// stable so callers can reason about side-effect ordering (announcements
    /// before the records that triggered them, active-match-id updates before
    /// the matching record arrives, etc.).
    public static func decode(_ payload: [String: Any]) -> [SyncIncomingEvent] {
        var events: [SyncIncomingEvent] = []

        if payload[MatchSyncKey.requestFullHistory] != nil {
            events.append(.requestFullHistory)
        }
        if payload["ping"] != nil {
            events.append(.ping)
        }
        if let rawValue = payload[MatchSyncKey.selectedTheme] as? String {
            events.append(.selectedTheme(rawValue))
        }
        if let text = payload[MatchSyncKey.liveAnnouncement] as? String,
           text.count <= maxAnnouncementLength {
            events.append(.announcement(text))
        }
        if payload[MatchSyncKey.clearActiveMatch] != nil {
            events.append(.clearActiveMatch)
        } else if let idString = payload[MatchSyncKey.activeMatchID] as? String,
                  let id = UUID(uuidString: idString) {
            events.append(.activeMatchID(id))
        }
        if let data = payload[MatchSyncKey.watchManifest] as? Data {
            do {
                let ids = try JSONDecoder().decode([String].self, from: data)
                guard ids.count <= maxManifestEntries else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: [],
                              debugDescription: "Manifest has \(ids.count) ids, exceeds cap of \(maxManifestEntries)")
                    )
                }
                events.append(.watchManifest(Set(ids.compactMap(UUID.init(uuidString:)))))
            } catch {
                events.append(.decodeError(key: MatchSyncKey.watchManifest, error: error))
            }
        }
        if payload[MatchSyncKey.deleteMatchOnWatch] != nil,
           let idString = payload[MatchSyncKey.deleteMatchID] as? String,
           let id = UUID(uuidString: idString) {
            events.append(.deleteMatchOnWatch(id))
        }
        // Numeric settings are range-checked so a corrupt peer can't persist a
        // nonsense value. 0 is a valid sentinel ("unset" / "auto") for the
        // birth-year and max-HR-override fields, so the lower bound is 0 there.
        if let year = payload[MatchSyncKey.userBirthYear] as? Int,
           year == 0 || birthYearRange.contains(year) {
            events.append(.userBirthYear(year))
        }
        if let override_ = payload[MatchSyncKey.userMaxHROverride] as? Int,
           (0...maxHeartRate).contains(override_) {
            events.append(.userMaxHROverride(override_))
        }
        if let v = payload[MatchSyncKey.statsTrackingEnabled] as? Bool { events.append(.statsTrackingEnabled(v)) }
        if let v = payload[MatchSyncKey.workoutSessionEnabled] as? Bool { events.append(.workoutSessionEnabled(v)) }
        if let v = payload[MatchSyncKey.checkChangeover] as? Bool { events.append(.checkChangeover(v)) }
        if let v = payload[MatchSyncKey.announcementsEnabled] as? Bool { events.append(.announcementsEnabled(v)) }
        if let v = payload[MatchSyncKey.iPhoneInputEnabled] as? Bool { events.append(.iPhoneInputEnabled(v)) }
        if let v = payload[MatchSyncKey.playerName] as? String {
            events.append(.playerName(String(v.prefix(maxPlayerNameLength))))
        }
        if let v = payload[MatchSyncKey.scoreCommand] as? String {
            let matchID = (payload[MatchSyncKey.scoreCommandMatchID] as? String).flatMap(UUID.init(uuidString:))
            events.append(.scoreCommand(command: v, matchID: matchID))
        }
        // Pending-point mirror (watch → phone). `clearPendingPoint` wins when
        // both keys are present so a stale `pendingPoint` field can never
        // re-open a sheet the watch has already closed.
        if payload[MatchSyncKey.clearPendingPoint] != nil {
            events.append(.clearPendingPoint)
        } else if let data = payload[MatchSyncKey.pendingPoint] as? Data {
            do {
                let info = try JSONDecoder().decode(PendingPointInfo.self, from: data)
                events.append(.pendingPoint(info))
            } catch {
                events.append(.decodeError(key: MatchSyncKey.pendingPoint, error: error))
            }
        }
        if let raw = payload[MatchSyncKey.pendingPointOutcome] as? String {
            if raw.isEmpty {
                events.append(.pendingPointOutcome(nil))
            } else if let outcome = PointOutcome(rawValue: raw) {
                events.append(.pendingPointOutcome(outcome))
            }
        }
        // Stat-action commands (phone → watch).
        if let action = payload[MatchSyncKey.statAction] as? String {
            let outcome = (payload[MatchSyncKey.statActionOutcome] as? String)
                .flatMap(PointOutcome.init(rawValue:))
            let endingShot = (payload[MatchSyncKey.statActionEndingShot] as? String)
                .flatMap(EndingShot.init(rawValue:))
            events.append(.statAction(action: action, outcome: outcome, endingShot: endingShot))
        }
        if let data = payload[MatchSyncKey.matchHistory] as? Data {
            do {
                let records = try MatchSyncMessage.decodeArray(data)
                events.append(.history(records))
            } catch {
                events.append(.decodeError(key: MatchSyncKey.matchHistory, error: error))
            }
        } else if let data = payload[MatchSyncKey.singleMatch] as? Data {
            do {
                let record = try MatchSyncMessage.decode(data)
                events.append(.singleMatch(record))
            } catch {
                events.append(.decodeError(key: MatchSyncKey.singleMatch, error: error))
            }
        }
        return events
    }

    /// Decodes a file-transfer payload identified by metadata `key`. Used by the
    /// phone's WCSessionDelegate file callback when large history payloads are
    /// pushed over `transferFile` instead of `transferUserInfo`.
    public static func decodeFile(data: Data, key: String) -> SyncIncomingEvent {
        do {
            switch key {
            case MatchSyncKey.matchHistory:
                return .history(try MatchSyncMessage.decodeArray(data))
            case MatchSyncKey.singleMatch:
                return .singleMatch(try MatchSyncMessage.decode(data))
            default:
                return .decodeError(
                    key: key,
                    error: NSError(domain: "SyncIncomingPayload",
                                   code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "Unknown file key: \(key)"])
                )
            }
        } catch {
            return .decodeError(key: key, error: error)
        }
    }
}
