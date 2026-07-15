// PhoneMatchSyncService.swift — WCSession delegate for the iPhone target.
//
// Owns the phone-specific concerns: published UI state about the watch session
// (reachable / paired / activation / outstanding transfers), routing decoded
// events to the local stats store and TTS service, and requesting a full
// history sync at activation. Transport plumbing (sendMessage / transferUserInfo /
// transferFile) lives in `MatchSyncTransport`; payload decoding in
// `SyncIncomingPayload`.
import Foundation
import Combine
import os
import WatchConnectivity
import DeuceMateCore

final class PhoneMatchSyncService: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneMatchSyncService()

    private let activationTimeout: TimeInterval
    private let isSessionSupported: () -> Bool
    private let activateSession: (WCSessionDelegate) -> Void
    private let scheduleAfter: (TimeInterval, DispatchWorkItem) -> Void
    private var activationTimeoutWorkItem: DispatchWorkItem?

    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var isWatchReachable: Bool = false
    @Published private(set) var isPaired: Bool = false
    /// True while WCSession activation is in progress, for at most 10 seconds.
    @Published private(set) var isActivating: Bool = true
    @Published private(set) var isWatchAppInstalled: Bool = false
    @Published private(set) var pendingTransferCount: Int = 0
    @Published private(set) var activationState: String = "notActivated"
    /// ID of the match currently active on the watch, or nil if none is running.
    @Published private(set) var activeMatchID: UUID? = nil
    /// Set of match IDs the watch most recently reported holding (its manifest).
    /// Used to badge each match's storage location. Cached in UserDefaults so the
    /// badge survives relaunch while the watch is unreachable.
    @Published private(set) var watchMatchIDs: Set<UUID> = PhoneMatchSyncService.loadCachedManifest()
    /// Mirror of the watch's match records (≤ its 25-match cap), so matches still
    /// on the watch but removed from the iPhone archive can be shown as full,
    /// tappable rows and restored. Refreshed from the watch's history/manifest
    /// pushes; persisted device-locally (see `mirrorFileURL`) so the rows survive
    /// relaunch while the watch is unreachable.
    @Published private(set) var watchMirror: [MatchRecord] = PhoneMatchSyncService.loadCachedMirror()

    /// Ids the watch is known to hold: its reported manifest unioned with the
    /// local mirror. The mirror can briefly contain a record whose id hasn't yet
    /// appeared in the manifest (the watch sends the record and the manifest as
    /// separate messages), so the union is the reliable "on watch" signal for
    /// storage-location badging — using `watchMatchIDs` alone would mislabel such
    /// a mirror-only row as "iPhone only" until the manifest catches up.
    var onWatchIDs: Set<UUID> {
        watchMatchIDs.union(watchMirror.map(\.id))
    }
    /// Mirror of the watch's current pending-point categorization, or nil when
    /// no point is awaiting classification. Set whenever the watch enters,
    /// updates, or rolls back its categorization sheet; cleared on commit /
    /// cancel / undo / match end.
    @Published private(set) var pendingPoint: PendingPointInfo? = nil
    /// Mirror of the watch's phase-1 selection. Non-nil when the watch has
    /// chosen an outcome and is awaiting an ending-shot selection (phase 2).
    @Published private(set) var pendingPointOutcome: PointOutcome? = nil

    /// True when WatchConnectivity could not start or did not finish activating
    /// within the bounded launch window. The iPhone archive and manual-entry
    /// flows remain fully usable in this state.
    var isActivationUnavailable: Bool {
        activationState == "Unavailable" || activationState == "Timed Out"
    }

    // Strong reference — incoming WCSession data must never be silently dropped
    // due to a deallocated store.
    private var store: PhoneStatsStore?
    /// Injected so live score announcements are spoken when the watch sends a point update.
    var announcementService: LiveAnnouncementService?

    private let transport = MatchSyncTransport(
        logger: Logger(subsystem: "com.deucemate.sync", category: "Phone")
    )
    private let logger = Logger(subsystem: "com.deucemate.sync", category: "Phone")

    init(
        activationTimeout: TimeInterval = 10,
        isSessionSupported: @escaping () -> Bool = { WCSession.isSupported() },
        activateSession: @escaping (WCSessionDelegate) -> Void = { delegate in
            let session = WCSession.default
            session.delegate = delegate
            session.activate()
        },
        scheduleAfter: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, workItem in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    ) {
        self.activationTimeout = activationTimeout
        self.isSessionSupported = isSessionSupported
        self.activateSession = activateSession
        self.scheduleAfter = scheduleAfter
        super.init()
    }

    // MARK: - Start

    func start(store: PhoneStatsStore) {
        self.store = store
        beginSessionActivation()
    }

    /// Starts WatchConnectivity and guarantees that the launch UI leaves its
    /// connecting state even when the platform never calls the activation
    /// delegate. Internal so the iOS target can test the state transition with
    /// injected session hooks rather than activating a real WCSession.
    func beginSessionActivation() {
        activationTimeoutWorkItem?.cancel()
        isActivating = true

        guard isSessionSupported() else {
            finishActivation(state: "Unavailable")
            return
        }

        activationState = "Activating"
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self, self.isActivating else { return }
            self.finishActivation(state: "Timed Out")
        }
        activationTimeoutWorkItem = timeoutWorkItem
        scheduleAfter(activationTimeout, timeoutWorkItem)
        activateSession(self)
    }

    /// Resolves the transient connecting state. A late activation callback may
    /// still replace a timeout label with the session's real state.
    func finishActivation(state: String) {
        activationTimeoutWorkItem?.cancel()
        activationTimeoutWorkItem = nil
        activationState = state
        isActivating = false
    }

    // MARK: - Outgoing (phone → watch)

    func ping(completion: @escaping (Bool, String) -> Void) {
        // Surface a friendlier hint when the watch isn't reachable.
        guard transport.isActivated else {
            completion(false, "Session not activated"); return
        }
        guard transport.isReachable else {
            completion(false, "Watch not reachable — open watch app and keep screen on"); return
        }
        transport.ping { ok, message in
            completion(ok, ok ? "Watch replied ✓" : message)
        }
    }

    func requestFullHistorySync() {
        transport.sendControl(MatchSyncPayloadBuilder.requestFullHistory(), queueOnFailure: true)
    }

    /// Ask the watch to delete a single match from its own store. The phone keeps
    /// its archive copy, so the match's badge flips from "both" to "iPhone only".
    /// Queued on failure so the command reaches the watch when it next connects.
    func sendDeleteMatchOnWatch(_ id: UUID) {
        transport.sendControl(
            MatchSyncPayloadBuilder.deleteMatchOnWatch(id),
            queueOnFailure: true
        )
    }

    /// Push a manually entered in-progress match to the watch so the user can
    /// resume scoring there. The watch normally owns active-match state; this
    /// is the one-way exception used by the manual-entry recovery flow. Queued
    /// on failure so the record arrives even if the watch isn't reachable now.
    func sendManualMatch(_ record: MatchRecord) {
        transport.sendRecordReliable(record)
    }

    /// Push a match the phone holds back to the watch ("Sync to Watch", used when
    /// a match was deleted from the watch but kept on the phone). Reuses the
    /// reliable single-record path; the watch appends it and replies with a fresh
    /// manifest, flipping the badge from "iPhone only" to "both". If the match is
    /// older than the watch's 25 most recent it may be trimmed straight back off
    /// — inherent to the watch's history cap; the phone can't predict it.
    func sendMatchToWatch(_ record: MatchRecord) {
        transport.sendRecordReliable(record)
    }

    /// Push the current Pulse Coach settings to the watch. Queued on failure so
    /// the watch eventually mirrors the latest values even if it was unreachable
    /// when the user toggled them. Only the user-entered birth year and max-HR
    /// override are sent; the watch computes the same resolved max HR locally
    /// from these, so there is no resolved value to push.
    func pushCurrentPulseCoachSettings() {
        let defaults = UserDefaults.standard
        pushPulseCoachSettings(
            birthYear: defaults.integer(forKey: "userBirthYear"),
            maxHROverride: defaults.integer(forKey: "userMaxHROverride")
        )
    }

    func pushPulseCoachSettings(birthYear: Int, maxHROverride: Int) {
        transport.sendControl(
            [
                MatchSyncKey.userBirthYear: birthYear,
                MatchSyncKey.userMaxHROverride: maxHROverride
            ],
            queueOnFailure: true
        )
    }

    func sendTheme(_ rawValue: String) {
        transport.sendControl([MatchSyncKey.selectedTheme: rawValue], queueOnFailure: true)
    }

    /// Push the two watch-only settings from the phone to the watch.
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

    /// Push the "iPhone Input" toggle to the watch (bidirectional, last-write wins).
    func pushIPhoneInputEnabled(_ enabled: Bool) {
        transport.sendControl([MatchSyncKey.iPhoneInputEnabled: enabled], queueOnFailure: true)
    }

    /// Push the player display name used in spoken announcements (bidirectional).
    func pushSharedPlayerName(_ name: String) {
        transport.sendControl([MatchSyncKey.playerName: name], queueOnFailure: true)
    }

    /// Send a spectator score command (winMe / winOpp / undo) to the watch.
    /// `matchID` is the UUID of the match the iPhone was displaying when the
    /// swipe happened. The watch rejects commands whose id doesn't match its
    /// current live match identity, so a stale `activeMatchID` on the phone
    /// (e.g. missed `clearActiveMatch`) cannot score points in an unrelated
    /// later match.
    ///
    /// Sent without queue-on-failure: a stale command queued for hours would
    /// be ignored by the matchID check anyway, and we want fast-fail semantics.
    /// The watch also ignores unknown commands and any commands when iPhone
    /// Input is disabled.
    func sendScoreCommand(_ command: String, matchID: UUID?) {
        var payload: [String: Any] = [MatchSyncKey.scoreCommand: command]
        if let id = matchID {
            payload[MatchSyncKey.scoreCommandMatchID] = id.uuidString
        }
        transport.sendControl(payload, queueOnFailure: false)
    }

    /// Send a post-point categorization action to the watch. Mirrors
    /// `sendScoreCommand` for the categorization sheet — the watch validates
    /// (must have a pending stat and iPhone Input enabled), applies via its
    /// existing `selectOutcome` / `commitEndingShot` / `cancelOutcomeSelection`
    /// paths, and pushes the resulting state back. Sent without queue-on-
    /// failure: a stale categorization queued for hours would be applied to a
    /// long-resolved point, so we want fast-fail semantics like score commands.
    func sendSelectOutcome(_ outcome: PointOutcome) {
        transport.sendControl(
            [
                MatchSyncKey.statAction: MatchSyncKey.statActionSelectOutcome,
                MatchSyncKey.statActionOutcome: outcome.rawValue
            ],
            queueOnFailure: false
        )
    }

    func sendCommitEndingShot(_ shot: EndingShot) {
        transport.sendControl(
            [
                MatchSyncKey.statAction: MatchSyncKey.statActionCommitEndingShot,
                MatchSyncKey.statActionEndingShot: shot.rawValue
            ],
            queueOnFailure: false
        )
    }

    func sendCancelOutcomeSelection() {
        transport.sendControl(
            [MatchSyncKey.statAction: MatchSyncKey.statActionCancelOutcomeSelection],
            queueOnFailure: false
        )
    }

    /// Roll the whole point back from the categorization panel. Routed through
    /// the stat-action path, not `sendScoreCommand`, because the watch rejects
    /// score commands while a stat is pending — the state the panel lives in.
    func sendUndoPoint() {
        transport.sendControl(
            [MatchSyncKey.statAction: MatchSyncKey.statActionUndoPoint],
            queueOnFailure: false
        )
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchReachable = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.pendingTransferCount = session.outstandingUserInfoTransfers.count
            self.finishActivation(state: Self.activationStateLabel(session.activationState))
        }
        if let error {
            logger.error("activation error: \(error.localizedDescription, privacy: .public)")
        }
        if activationState == .activated {
            requestFullHistorySync()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.beginSessionActivation()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
            self.pendingTransferCount = session.outstandingUserInfoTransfers.count
        }
        if session.isReachable {
            requestFullHistorySync()
        }
    }

    // MARK: - Incoming (watch → phone)

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(SyncIncomingPayload.decode(userInfo))
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(SyncIncomingPayload.decode(message))
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handle(SyncIncomingPayload.decode(message))
        replyHandler([:])
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let key = file.metadata?["key"] as? String else { return }
        // Only history/single-match payloads arrive as files; reject any other key
        // before touching the contents.
        guard key == MatchSyncKey.matchHistory || key == MatchSyncKey.singleMatch else {
            logger.error("ignoring incoming file with unexpected key: \(key, privacy: .public)")
            return
        }
        do {
            // Bound the read before buffering the file into memory, reusing the
            // manual-import ceiling so an oversized transfer can't OOM the reader.
            let values = try file.fileURL.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize,
               size > ManualMatchArchiveBackup.maxArchiveBytes {
                logger.error("ignoring oversized incoming file: \(size) bytes")
                return
            }
            let data = try Data(contentsOf: file.fileURL)
            handle([SyncIncomingPayload.decodeFile(data: data, key: key)])
        } catch {
            logger.error("failed to read incoming file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func handle(_ events: [SyncIncomingEvent]) {
        var didSync = false
        for event in events {
            switch event {
            case .announcement(let text):
                DispatchQueue.main.async { self.announcementService?.speak(text) }
            case .clearActiveMatch:
                DispatchQueue.main.async {
                    self.activeMatchID = nil
                    self.announcementService?.setMatchLive(false)
                }
            case .activeMatchID(let id):
                DispatchQueue.main.async {
                    self.activeMatchID = id
                    self.announcementService?.setMatchLive(true)
                }
            case .watchManifest(let ids):
                DispatchQueue.main.async {
                    self.watchMatchIDs = ids
                    Self.cacheManifest(ids)
                    self.updateMirror { WatchMirror.pruned($0, manifest: ids) }
                }
            case .history(let records):
                store?.mergeIncoming(records)
                DispatchQueue.main.async {
                    self.updateMirror {
                        WatchMirror.merged(existing: $0, incoming: records, manifest: self.watchMatchIDs)
                    }
                }
                didSync = true
            case .singleMatch(let record):
                store?.mergeIncoming(record)
                DispatchQueue.main.async {
                    self.updateMirror {
                        WatchMirror.merged(existing: $0, incoming: [record], manifest: self.watchMatchIDs)
                    }
                }
                didSync = true
            case .selectedTheme(let rawValue):
                DispatchQueue.main.async {
                    UserDefaults.standard.set(rawValue, forKey: "selectedTheme")
                }
            case .announcementsEnabled(let v):
                DispatchQueue.main.async {
                    self.announcementService?.setEnabled(v)
                }
            case .userBirthYear(let v):
                DispatchQueue.main.async {
                    UserDefaults.standard.set(v, forKey: "userBirthYear")
                    self.pushCurrentPulseCoachSettings()
                }
            case .userMaxHROverride(let v):
                DispatchQueue.main.async {
                    UserDefaults.standard.set(v, forKey: "userMaxHROverride")
                    self.pushCurrentPulseCoachSettings()
                }
            case .statsTrackingEnabled(let v):
                DispatchQueue.main.async { UserDefaults.standard.set(v, forKey: "statsTrackingEnabled") }
            case .workoutSessionEnabled:
                break
            case .checkChangeover(let v):
                DispatchQueue.main.async { UserDefaults.standard.set(v, forKey: "checkChangeover") }
            case .iPhoneInputEnabled(let v):
                DispatchQueue.main.async {
                    UserDefaults.standard.set(v, forKey: "iPhoneInputEnabled")
                }
            case .playerName(let v):
                DispatchQueue.main.async {
                    UserDefaults.standard.set(v, forKey: "playerName")
                }
            case .pendingPoint(let info):
                DispatchQueue.main.async {
                    self.pendingPoint = info
                    // The watch sends `pendingPointOutcome` in the same payload
                    // when it's non-nil. If the message omitted it, treat as
                    // phase 1 (no outcome chosen yet) — important for the
                    // "rolled back to phase 1" path.
                }
            case .pendingPointOutcome(let outcome):
                DispatchQueue.main.async { self.pendingPointOutcome = outcome }
            case .clearPendingPoint:
                DispatchQueue.main.async {
                    self.pendingPoint = nil
                    self.pendingPointOutcome = nil
                }
            case .requestFullHistory, .ping, .scoreCommand, .statAction,
                 .deleteMatchOnWatch:
                // scoreCommand / statAction / deleteMatchOnWatch are phone → watch
                // only; the phone ignores any echo (matchID / action payloads are
                // decoded but not actioned on this side).
                break
            case .decodeError(let key, let error):
                logger.error("decode error for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if didSync { markSynced() }
    }

    /// UserDefaults key for the cached watch manifest. Phone-local persistence —
    /// not a synced setting, so it intentionally does not mirror a `MatchSyncKey`.
    private static let watchManifestCacheKey = "watchManifestIDs"

    private static func loadCachedManifest() -> Set<UUID> {
        let strings = UserDefaults.standard.stringArray(forKey: watchManifestCacheKey) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    private static func cacheManifest(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: watchManifestCacheKey)
    }

    // MARK: - Watch mirror persistence (device-local; never iCloud)

    /// File holding the phone's mirror of the watch's records. Lives in the app's
    /// Documents directory — NOT the iCloud container — because it reflects *this*
    /// paired watch's current state, not user archive data. (PhoneStatsStore's
    /// iCloud migration intentionally leaves it out for the same reason.) Full
    /// records (with stats) are too large for UserDefaults, so it is a JSON file.
    private static var mirrorFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watchMirror.json")
    }

    /// Serial queue for mirror file I/O so writes never block the main thread.
    private static let mirrorIOQueue = DispatchQueue(
        label: "com.deucemate.phone.watchmirror", qos: .utility
    )

    private static func loadCachedMirror() -> [MatchRecord] {
        guard let data = try? Data(contentsOf: mirrorFileURL),
              let records = try? JSONDecoder().decode([MatchRecord].self, from: data)
        else { return [] }
        return records
    }

    private static func cacheMirror(_ records: [MatchRecord]) {
        mirrorIOQueue.async {
            guard let data = try? JSONEncoder().encode(records) else { return }
            // The mirror is refreshed from background WatchConnectivity callbacks,
            // which can fire while the device is locked — `.completeFileProtection`
            // would make the write fail then. `UntilFirstUserAuthentication` keeps
            // it writable after the first post-boot unlock.
            try? data.write(
                to: mirrorFileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        }
    }

    /// Apply `transform` to the current mirror, publish the result, and persist
    /// it. Must run on the main thread — it mutates the `@Published` mirror.
    private func updateMirror(_ transform: ([MatchRecord]) -> [MatchRecord]) {
        let updated = transform(watchMirror)
        watchMirror = updated
        Self.cacheMirror(updated)
    }

    private func markSynced() {
        DispatchQueue.main.async {
            self.lastSyncDate = Date()
            self.pendingTransferCount = WCSession.default.outstandingUserInfoTransfers.count
        }
    }

    private static func activationStateLabel(_ state: WCSessionActivationState) -> String {
        switch state {
        case .notActivated: return "Not Activated"
        case .inactive:     return "Inactive"
        case .activated:    return "Activated"
        @unknown default:   return "Unknown"
        }
    }
}
