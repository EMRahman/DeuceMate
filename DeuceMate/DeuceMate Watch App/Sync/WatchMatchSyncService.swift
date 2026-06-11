// WatchMatchSyncService.swift — WCSession delegate for the watch target.
//
// Thin glue layer: the actual transport choice (sendMessage vs transferUserInfo
// vs transferFile) lives in `MatchSyncTransport`, and inbound payload decoding
// lives in `SyncIncomingPayload`. This file owns only watch-specific behaviour:
// kicking a full-history push when the phone activates or becomes reachable,
// and replying to the phone's history requests.
import Foundation
import os
import WatchConnectivity
import DeuceMateCore

final class WatchMatchSyncService: NSObject, MatchSyncService, WCSessionDelegate {

    static let shared = WatchMatchSyncService()

    private(set) var lastSyncDate: Date?

    /// Called on the main thread when the paired iPhone sends a theme change.
    var onThemeReceived: ((String) -> Void)?
    var onStatsTrackingReceived: ((Bool) -> Void)?
    var onChangeoverReceived: ((Bool) -> Void)?
    /// Called on the main thread when the phone pushes the shared announcements setting.
    var onAnnouncementsReceived: ((Bool) -> Void)?
    /// Called on the main thread when the phone pushes the "iPhone Input" toggle.
    var onIPhoneInputReceived: ((Bool) -> Void)?
    /// Called on the main thread when the phone pushes the player display name.
    var onPlayerNameReceived: ((String) -> Void)?
    /// Called on the main thread when the phone sends a spectator score command
    /// (one of `MatchSyncKey.scoreCommandWinMe` / `scoreCommandWinOpp` / `scoreCommandUndo`).
    /// `matchID` is the UUID of the match the iPhone was displaying when the
    /// swipe happened; the watch must reject the command unless this matches
    /// its own current live match identity.
    var onScoreCommandReceived: ((_ command: String, _ matchID: UUID?) -> Void)?
    /// Called on the main thread when the iPhone issues a post-point
    /// categorization action (select outcome / commit ending shot / cancel).
    /// Mirrors `onScoreCommandReceived` for the categorization sheet.
    var onStatActionReceived: ((_ action: String, _ outcome: PointOutcome?, _ endingShot: EndingShot?) -> Void)?

    private let transport = MatchSyncTransport(
        logger: Logger(subsystem: "com.deucemate.sync", category: "Watch")
    )
    private let logger = Logger(subsystem: "com.deucemate.sync", category: "Watch")

    // MARK: - MatchSyncService

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendMatch(_ record: MatchRecord, announcement: String? = nil) {
        transport.sendRecord(
            record,
            completedClearsActive: !record.isInProgress,
            announcement: announcement
        )
        // Only when a match completes does the watch's stored *set* meaningfully
        // change for the phone's badge — in-progress checkpoints fire per point
        // and would spam the manifest. Activation/reachability full-history syncs
        // refresh the manifest the rest of the time.
        if !record.isInProgress {
            sendManifest()
        }
    }

    /// Push the watch's current set of match IDs to the phone so it can badge each
    /// match's storage location. Cheap (≤10 UUID strings). Queued on failure so the
    /// phone's cached manifest eventually catches up even if the watch is
    /// unreachable when the local history changes.
    func sendManifest() {
        let ids = StatsStore.shared.loadHistory().map(\.id)
        guard let payload = try? MatchSyncPayloadBuilder.watchManifest(ids) else { return }
        transport.sendControl(payload, queueOnFailure: true)
    }

    func sendTheme(_ rawValue: String) {
        transport.sendControl([MatchSyncKey.selectedTheme: rawValue], queueOnFailure: true)
    }

    func sendAnnouncement(_ text: String, completion: @escaping (Bool) -> Void) {
        transport.sendAnnouncement(text, completion: completion)
    }

    func clearActiveMatch() {
        // No queue-on-failure: the phone re-derives state on the next sync,
        // so dropping this when unreachable is intentional.
        transport.sendControl([MatchSyncKey.clearActiveMatch: true], queueOnFailure: false)
    }

    func sendFullHistory(_ records: [MatchRecord]) {
        transport.sendHistory(records)
        sendManifest()
    }

    // MARK: - Watch → phone setting pushes

    /// Push the two watch-only settings from the watch to the phone (bidirectional, last-write wins).
    func pushWatchOnlySettings(statsTracking: Bool, changeover: Bool) {
        transport.sendControl(
            [
                MatchSyncKey.statsTrackingEnabled: statsTracking,
                MatchSyncKey.checkChangeover: changeover
            ],
            queueOnFailure: true
        )
    }

    func pushSharedAnnouncements(_ enabled: Bool) {
        transport.sendControl([MatchSyncKey.announcementsEnabled: enabled], queueOnFailure: true)
    }

    /// Push the "iPhone Input" toggle to the phone (bidirectional, last-write wins).
    func pushIPhoneInputEnabled(_ enabled: Bool) {
        transport.sendControl([MatchSyncKey.iPhoneInputEnabled: enabled], queueOnFailure: true)
    }

    /// Push the player display name used in spoken announcements (bidirectional).
    func pushSharedPlayerName(_ name: String) {
        transport.sendControl([MatchSyncKey.playerName: name], queueOnFailure: true)
    }

    /// Push the current pending-point categorization state to the phone. Sent
    /// whenever the watch enters, advances, or rolls back its categorization
    /// sheet. `pending == nil` is encoded as `clearPendingPoint` so the phone
    /// dismisses any sheet that's still up. Not queued on failure: the phone
    /// re-derives state from the next saved checkpoint, so a dropped pending
    /// message is harmless and we want fast-fail semantics — same posture as
    /// the score commands.
    func sendPendingPointState(_ pending: PendingPointInfo?, outcome: PointOutcome?) {
        var payload: [String: Any] = [:]
        if let pending {
            do {
                payload[MatchSyncKey.pendingPoint] = try JSONEncoder().encode(pending)
            } catch {
                logger.error("encode pendingPoint failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            // Empty string signals "no outcome chosen yet" (phase 1). Sending an
            // explicit key avoids the phone treating "missing" as "unchanged".
            payload[MatchSyncKey.pendingPointOutcome] = outcome?.rawValue ?? ""
        } else {
            payload[MatchSyncKey.clearPendingPoint] = true
        }
        transport.sendControl(payload, queueOnFailure: false)
    }

    /// Watch → phone push of the player's birth year (0 means unset / "Skip").
    /// `fromHealth` is true when the value was sourced from the user's Health
    /// record on the watch, so the phone can label the value accordingly.
    func pushSharedUserBirthYear(_ year: Int, fromHealth: Bool) {
        transport.sendControl(
            [
                MatchSyncKey.userBirthYear: year,
                MatchSyncKey.userBirthYearFromHealth: fromHealth
            ],
            queueOnFailure: true
        )
    }

    /// Watch → phone push of the manual max-HR override (0 means auto).
    func pushSharedUserMaxHROverride(_ bpm: Int) {
        transport.sendControl([MatchSyncKey.userMaxHROverride: bpm], queueOnFailure: true)
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("activation error: \(error.localizedDescription, privacy: .public)")
        }
        guard activationState == .activated else { return }
        sendFullHistory(StatsStore.shared.loadHistory())
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        sendFullHistory(StatsStore.shared.loadHistory())
    }

    // MARK: - Receive requests from phone

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handle(message)
        replyHandler([:])
    }

    // MARK: - Private

    private func handle(_ payload: [String: Any]) {
        for event in SyncIncomingPayload.decode(payload) {
            switch event {
            case .requestFullHistory, .ping:
                sendFullHistory(StatsStore.shared.loadHistory())
            case .pulseCoachMaxHR(let bpm):
                DispatchQueue.main.async {
                    UserDefaults.standard.set(bpm, forKey: "pulseCoachMaxHR")
                    NotificationCenter.default.post(
                        name: .pulseCoachSettingsChanged,
                        object: nil
                    )
                }
            case .userBirthYear(let year):
                DispatchQueue.main.async {
                    UserDefaults.standard.set(year, forKey: "userBirthYear")
                    NotificationCenter.default.post(
                        name: .pulseCoachSettingsChanged,
                        object: nil
                    )
                }
            case .userBirthYearFromHealth(let fromHealth):
                DispatchQueue.main.async {
                    UserDefaults.standard.set(fromHealth, forKey: "userBirthYearFromHealth")
                    NotificationCenter.default.post(
                        name: .pulseCoachSettingsChanged,
                        object: nil
                    )
                }
            case .userMaxHROverride(let bpm):
                DispatchQueue.main.async {
                    UserDefaults.standard.set(bpm, forKey: "userMaxHROverride")
                    NotificationCenter.default.post(
                        name: .pulseCoachSettingsChanged,
                        object: nil
                    )
                }
            case .selectedTheme(let rawValue):
                DispatchQueue.main.async { self.onThemeReceived?(rawValue) }
            case .statsTrackingEnabled(let v):
                DispatchQueue.main.async { self.onStatsTrackingReceived?(v) }
            case .workoutSessionEnabled:
                break
            case .checkChangeover(let v):
                DispatchQueue.main.async { self.onChangeoverReceived?(v) }
            case .announcementsEnabled(let v):
                DispatchQueue.main.async { self.onAnnouncementsReceived?(v) }
            case .iPhoneInputEnabled(let v):
                DispatchQueue.main.async { self.onIPhoneInputReceived?(v) }
            case .playerName(let v):
                DispatchQueue.main.async { self.onPlayerNameReceived?(v) }
            case .scoreCommand(let cmd, let matchID):
                DispatchQueue.main.async { self.onScoreCommandReceived?(cmd, matchID) }
            case .statAction(let action, let outcome, let endingShot):
                DispatchQueue.main.async {
                    self.onStatActionReceived?(action, outcome, endingShot)
                }
            case .deleteMatchOnWatch(let id):
                // Phone asked to free this match from the watch only; the phone
                // keeps its own archive copy. Remove locally and re-publish the
                // manifest so the phone's badge flips to "iPhone only".
                StatsStore.shared.removeMatch(id: id)
                sendManifest()
            case .singleMatch(let record):
                // The phone pushes a record back to the watch for the manual-entry
                // recovery flow and for "Sync to Watch". Append into the watch's
                // history (so it appears in MatchHistoryView) and re-publish the
                // manifest so the phone learns the watch now holds it — its badge
                // flips from "iPhone only" to "both".
                StatsStore.shared.appendMatch(record)
                sendManifest()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .watchMatchHistoryDidChange, object: nil)
                }
            case .decodeError(let key, let error):
                logger.error("decode error for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            default:
                break
            }
        }
    }
}

extension Notification.Name {
    static let pulseCoachSettingsChanged = Notification.Name("PulseCoachSettingsChanged")
    static let watchMatchHistoryDidChange = Notification.Name("WatchMatchHistoryDidChange")
}
