//ScoreViewModel.swift
import Foundation
import SwiftUI
import Combine
import HealthKit
import CoreLocation
import os
import DeuceMateCore

private let scoreStateLogger = Logger(subsystem: "com.deucemate.persistence", category: "WatchAppState")

struct ChangeoverInfo: Identifiable {
    let id = UUID()
    let symbol: String
    let reason: String
}

class ScoreViewModel: ObservableObject {
    private static let userDefaultsQueue = DispatchQueue(label: "com.deucemate.userdefaults", qos: .utility)

    /// Persistence failures worth telling the user about — a failed live-match
    /// save, an unreadable restore, or a history write the store rejected.
    /// Written on the main queue only (`saveState`/`loadState` run there, and
    /// `StatsStore` reports its outcomes back on main). Rendered as a full
    /// banner by `PersistenceWarningBanner` on the start screen, and — for
    /// critical failures only, which happen mid-match — as a dismissible corner
    /// chip on the live scoreboard.
    @Published private(set) var persistenceHealth = PersistenceHealth()

    @Published var currentServer: Player? = nil
    @Published var gameCount: Int = 0
    @Published var pointCountInTiebreak: Int = 0
    @Published var pendingChangeoverAck: ChangeoverInfo? = nil
    private var isSyncingStats = false
    @Published var statsTrackingEnabled: Bool = UserDefaults.standard.object(forKey: "statsTrackingEnabled") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(statsTrackingEnabled, forKey: "statsTrackingEnabled")
            detailedShotTrackingEnabled = statsTrackingEnabled
            if !statsTrackingEnabled {
                // Toggling off mid-match: drop any open categorization sheet
                // and clear the second-serve flag so the live UI stops showing
                // stats-related state. In-memory currentMatchStats is preserved
                // until the next resetMatch / new match start so the user can
                // still glance at what they collected.
                discardAllPendingState()
                isOnSecondServe = false
            }
            guard !isSyncingStats else { return }
            WatchMatchSyncService.shared.pushWatchOnlySettings(
                statsTracking: statsTrackingEnabled,
                changeover: checkChangeover)
        }
    }
    /// Mirrors `statsTrackingEnabled` — detailed shot tracking is always on
    /// when point-outcome tracking is on. There is no "basic" mode.
    @Published var detailedShotTrackingEnabled: Bool = false {
        didSet {
            if !detailedShotTrackingEnabled {
                pendingOutcome = nil
            }
        }
    }
    let workoutManager = WorkoutManager()
    private var cancellables = Set<AnyCancellable>()
    private var isSyncingChangeover_ = false
    @Published var checkChangeover: Bool = UserDefaults.standard.object(forKey: "checkChangeover") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(checkChangeover, forKey: "checkChangeover")
            guard !isSyncingChangeover_ else { return }
            WatchMatchSyncService.shared.pushWatchOnlySettings(
                statsTracking: statsTrackingEnabled,
                changeover: checkChangeover)
        }
    }

    func applyIncomingStatsTracking(_ v: Bool) {
        guard v != statsTrackingEnabled else { return }
        isSyncingStats = true; statsTrackingEnabled = v; isSyncingStats = false
    }
    func applyIncomingChangeover(_ v: Bool) {
        guard v != checkChangeover else { return }
        isSyncingChangeover_ = true; checkChangeover = v; isSyncingChangeover_ = false
    }
    private var isSyncingTheme = false
    @Published var selectedTheme: AppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "selectedTheme") ?? "") ?? .default {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "selectedTheme")
            guard !isSyncingTheme else { return }
            WatchMatchSyncService.shared.sendTheme(selectedTheme.rawValue)
        }
    }

    /// Applies a theme received from the paired iPhone without echoing it back.
    func applyIncomingTheme(_ rawValue: String) {
        guard let theme = AppTheme(rawValue: rawValue), theme != selectedTheme else { return }
        isSyncingTheme = true
        selectedTheme = theme
        isSyncingTheme = false
    }
    private var isSyncingAnnouncements = false
    @Published var phoneAnnouncementsEnabled: Bool = UserDefaults.standard.object(forKey: "phoneAnnouncementsEnabled") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(phoneAnnouncementsEnabled, forKey: "phoneAnnouncementsEnabled")
            guard !isSyncingAnnouncements else { return }
            WatchMatchSyncService.shared.pushSharedAnnouncements(phoneAnnouncementsEnabled)
        }
    }

    /// Apply an announcements value from the phone without echoing it back.
    func applyIncomingAnnouncements(_ enabled: Bool, pushToPhone: Bool = false) {
        guard enabled != phoneAnnouncementsEnabled else { return }
        isSyncingAnnouncements = true
        phoneAnnouncementsEnabled = enabled
        isSyncingAnnouncements = false
        if pushToPhone {
            WatchMatchSyncService.shared.pushSharedAnnouncements(enabled)
        }
    }
    /// Player birth year used to derive max HR when no override is set.
    /// 0 means "Skip" (unset). User-entered; bidirectionally synced with the iPhone.
    @Published var userBirthYear: Int = UserDefaults.standard.integer(forKey: "userBirthYear") {
        didSet {
            UserDefaults.standard.set(userBirthYear, forKey: "userBirthYear")
        }
    }

    /// True when `userMaxHROverride` falls within the valid range that
    /// `HRZone.resolveMaxHR` will actually honour (120–220 bpm).
    var isHROverrideActive: Bool { HRZone.isValidOverride(userMaxHROverride) }

    /// Manual max-HR override in bpm. 0 means auto. Bidirectionally synced with the iPhone.
    @Published var userMaxHROverride: Int = UserDefaults.standard.integer(forKey: "userMaxHROverride") {
        didSet {
            UserDefaults.standard.set(userMaxHROverride, forKey: "userMaxHROverride")
        }
    }

    /// Re-reads the persisted Pulse Coach values into the published properties so
    /// SwiftUI bindings reflect phone-pushed changes. Called from the
    /// `.pulseCoachSettingsChanged` observer below.
    fileprivate func refreshPulseCoachValuesFromDefaults() {
        let by = UserDefaults.standard.integer(forKey: "userBirthYear")
        if by != userBirthYear { userBirthYear = by }
        let mo = UserDefaults.standard.integer(forKey: "userMaxHROverride")
        if mo != userMaxHROverride { userMaxHROverride = mo }
    }
    let momentumEnabled = true

    private var isSyncingIPhoneInput = false
    /// When true, the iPhone live scoreboard accepts swipe gestures (win / lose / undo)
    /// from a spectator and forwards them to the watch as score commands.
    /// Bidirectional, last-write wins.
    @Published var iPhoneInputEnabled: Bool = UserDefaults.standard.object(forKey: "iPhoneInputEnabled") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(iPhoneInputEnabled, forKey: "iPhoneInputEnabled")
            guard !isSyncingIPhoneInput else { return }
            WatchMatchSyncService.shared.pushIPhoneInputEnabled(iPhoneInputEnabled)
        }
    }

    /// Apply an iPhone-input value from the phone without echoing it back.
    func applyIncomingIPhoneInput(_ enabled: Bool, pushToPhone: Bool = false) {
        guard enabled != iPhoneInputEnabled else { return }
        isSyncingIPhoneInput = true
        iPhoneInputEnabled = enabled
        isSyncingIPhoneInput = false
        if pushToPhone {
            WatchMatchSyncService.shared.pushIPhoneInputEnabled(enabled)
        }
    }

    /// Apply a scoring command received from the iPhone spectator. Gated by
    /// `iPhoneInputEnabled` (defence in depth — the iPhone shouldn't send when
    /// disabled, but in-flight messages can arrive moments after the watch
    /// flips the flag off). Routes through the same `winPoint` / `losePoint` /
    /// `undo` entry points the on-watch swipe handler uses, so haptics, stats
    /// categorisation, atomic file writes and phone-sync all run unchanged.
    ///
    /// `matchID` is the UUID of the match the iPhone was displaying when the
    /// swipe happened. The command is dropped unless this matches the watch's
    /// own current live match identity — that way a stale `activeMatchID` on
    /// the phone (e.g. missed `clearActiveMatch`) cannot score points in an
    /// unrelated later match. A `nil` matchID is also rejected: every iPhone
    /// build that emits score commands includes the id, so a missing id
    /// indicates a malformed/legacy payload that we don't trust.
    /// Apply a post-point categorization action issued by the paired iPhone.
    /// Mirrors `applyRemoteScoreCommand` but for the categorization sheet: the
    /// phone sends `selectOutcome`, `commitEndingShot`, or
    /// `cancelOutcomeSelection`, and we drive the existing watch-side methods
    /// just as if the user had tapped the watch's own sheet.
    ///
    /// Gated by `iPhoneInputEnabled` and by the presence of a pending stat —
    /// without one there's nothing to categorize. The pending state's property
    /// observers would normally echo each mutation back to the phone, but the
    /// phone already drove this change so we suppress the round-trip and emit
    /// a single coalesced update at the end.
    func applyRemoteStatAction(_ action: String, outcome: PointOutcome?, endingShot: EndingShot?) {
        guard iPhoneInputEnabled else { return }
        guard pendingStatPoint != nil else { return }

        isApplyingRemoteStatAction = true
        defer {
            isApplyingRemoteStatAction = false
            // Emit one update reflecting the final state. The phone uses this
            // both to advance to phase 2 and to dismiss on commit/cancel.
            pushPendingPointToPhone()
        }

        switch action {
        case MatchSyncKey.statActionSelectOutcome:
            guard let outcome else { return }
            selectOutcome(outcome)
        case MatchSyncKey.statActionCommitEndingShot:
            guard let endingShot else { return }
            commitEndingShot(endingShot)
        case MatchSyncKey.statActionCancelOutcomeSelection:
            cancelOutcomeSelection()
        case MatchSyncKey.statActionUndoPoint:
            // Mirrors the watch sheet's "Undo point" button, which calls
            // `undo()` directly. Routed here (not via applyRemoteScoreCommand)
            // because that path rejects score commands while a stat is pending.
            undo()
        default:
            break
        }
    }

    func applyRemoteScoreCommand(_ command: String, matchID: UUID?) {
        guard iPhoneInputEnabled else { return }
        guard let incomingID = matchID, let liveID = currentMatchID, incomingID == liveID else {
            return
        }
        // Mirror the on-watch swipe guards (see ContentView.handleSwipe): a
        // pending categorisation sheet / changeover ack / doubles decision
        // means the watch is awaiting user input and can't safely score.
        if pendingStatPoint != nil { return }
        if pendingChangeoverAck != nil { return }
        if isChangeoverPending { return }
        if needsDoublesTeamServerDecision && gameCount > 0 { return }

        switch command {
        case MatchSyncKey.scoreCommandWinMe:
            guard !isMatchComplete() else { return }
            winPoint(player: .me)
        case MatchSyncKey.scoreCommandWinOpp:
            guard !isMatchComplete() else { return }
            losePoint(player: .me)
        case MatchSyncKey.scoreCommandUndo:
            undo()
        default:
            break
        }
    }
    private var isSyncingPlayerName = false
    @Published var playerName: String = UserDefaults.standard.string(forKey: "playerName") ?? "" {
        didSet {
            UserDefaults.standard.set(playerName, forKey: "playerName")
            guard !isSyncingPlayerName else { return }
            WatchMatchSyncService.shared.pushSharedPlayerName(playerName)
        }
    }

    /// Apply a player name value from the phone without echoing it back.
    func applyIncomingPlayerName(_ name: String, pushToPhone: Bool = false) {
        guard name != playerName else { return }
        isSyncingPlayerName = true
        playerName = name
        isSyncingPlayerName = false
        if pushToPhone {
            WatchMatchSyncService.shared.pushSharedPlayerName(name)
        }
    }
    @Published var courtInitialHeading: Double? = UserDefaults.standard.object(forKey: "courtInitialHeading") as? Double {
        didSet {
            let value = courtInitialHeading
            Self.userDefaultsQueue.async {
                UserDefaults.standard.set(value, forKey: "courtInitialHeading")
            }
        }
    }
    @Published var currentDeviceHeading: Double? = nil
    @Published var currentHeadingAccuracy: Double = -1
    private var headingManager: HeadingManager? = nil
    @Published var pendingStatPoint: PendingPointInfo? = nil {
        didSet {
            guard !isApplyingRemoteStatAction,
                  oldValue != pendingStatPoint else { return }
            pushPendingPointToPhone()
        }
    }
    /// Phase-1 selection of the two-step categorization sheet. Set after the
    /// user picks an outcome; cleared on commit, undo, or back. nil while the
    /// sheet is on its outcome step (or when detailed tracking is off).
    @Published var pendingOutcome: PointOutcome? = nil {
        didSet {
            guard !isApplyingRemoteStatAction,
                  oldValue != pendingOutcome else { return }
            pushPendingPointToPhone()
        }
    }
    /// Re-entrancy guard. When `applyRemoteStatAction` mutates pending state in
    /// response to an iPhone command, the property observers must not echo the
    /// resulting state back to the phone — the phone has the same view already
    /// and a redundant round-trip can race with the watch's own next message.
    private var isApplyingRemoteStatAction: Bool = false

    /// Mirror the watch's current categorization context to the paired phone.
    /// Lightweight enough to call on every pending-state mutation: a single
    /// WCSession control payload with either the encoded `PendingPointInfo`
    /// plus chosen outcome (if any), or a `clearPendingPoint` flag.
    private func pushPendingPointToPhone() {
        syncService?.sendPendingPointState(pendingStatPoint, outcome: pendingOutcome)
    }
    private var pendingAnnouncementInfo: ChangeoverInfo?
    private var pendingAnnouncementWorkItem: DispatchWorkItem?
    @Published private(set) var currentMatchStats: [PointStat] = []
    @Published var matchStartTime: Date? = nil
    @Published var showStatsView: Bool = false
    @Published var showHistoryView: Bool = false
    @Published var isOnSecondServe: Bool = false
    /// When set to true, HomeView should close the history sheet and open the match view.
    @Published var shouldOpenMatchView: Bool = false
    /// Start of the current active play session (reset each resume/relaunch).
    @Published var sessionStartTime: Date? = nil
    /// Accumulated play seconds from all prior sessions (excludes parked/killed time).
    @Published var matchElapsedSeconds: TimeInterval = 0
    /// Per-set accumulated active-play seconds from all prior sessions. Keyed by set index.
    @Published var setElapsedSeconds: [Int: TimeInterval] = [:]
    /// When the current set's play began in this session (reset on resume/relaunch/set transition).
    var currentSetSessionStart: Date? = nil
    /// ID of the in-progress MatchRecord. Generated lazily on first point of a
    /// match so that resume-then-park reuses the same id (no duplicates).
    /// Internal-readable so views can detect "this stored record IS the live
    /// match" and skip the replace-confirm alert.
    private(set) var currentMatchID: UUID? = nil
    @Published private(set) var tiebreakStartServer: Player? = nil
    @Published private(set) var tiebreakFirstPointReceiver: Player? = nil
    @Published private(set) var lastTiebreakPointServer: Player? = nil
    @Published var matchType: MatchType = .singles
    @Published var matchFormat: MatchFormat = .standard
    var isTiebreakOnlyFormat: Bool { !matchFormat.config.playRegularSets }
    @Published var doublesServer: DoublesServer? = nil
    @Published var needsDoublesTeamServerDecision: Bool = false
    var doublesServiceOrder: [DoublesServer] = []
    private var doublesServiceIndex: Int = 0
    private var tiebreakStartDoublesIndex: Int = 0
    /// Injected sync service. Set by the app entry point after WCSession is ready.
    var syncService: (any MatchSyncService)? {
        didSet {
            // If we resumed a kill-mid-flow state, the pending-point property
            // observers fired before `syncService` was wired up — the phone
            // missed that initial mirror. Push current state once on
            // assignment so the phone's sheet appears as soon as WCSession
            // reaches it.
            if pendingStatPoint != nil {
                pushPendingPointToPhone()
            }
        }
    }
    /// TTS string to send to the iPhone with the next saveState() call. Cleared after each send.
    private var pendingPhoneAnnouncement: String?

    // Player, MatchType, MatchFormat, DoublesServer, SetScore are defined in
    // DeuceMateCore and aliased into ScoreViewModel in MatchStats.swift.
    
    struct HistoryEntry: Codable {
        let player: Player
        let action: String
        let sets: [SetScore]
        let currentPointsMe: Int
        let currentPointsOpponent: Int
        let currentServer: Player?
        let gameCount: Int
        let pointCountInTiebreak: Int

        let tiebreakStartServer: Player?
        let tiebreakFirstPointReceiver: Player?
        let lastTiebreakPointServer: Player?

        /// Snapshot of `isOnSecondServe` *before* the point was scored, so undo
        /// can restore the serve state of the prior point. v2 field; defaults
        /// to false when decoding v1 saves.
        let isOnSecondServe: Bool
        /// Stable ID of the PointStat appended for this point, if any. Lets
        /// `undo()` remove the exact stat by id rather than blindly dropping
        /// the last element (which is wrong if a prior point was uncategorized,
        /// or if stats tracking was toggled mid-match).
        let committedStatID: UUID?
        let doublesServer: DoublesServer?
        let doublesServiceIndex: Int

        init(player: Player,
             action: String,
             sets: [SetScore],
             currentPointsMe: Int,
             currentPointsOpponent: Int,
             currentServer: Player?,
             gameCount: Int,
             pointCountInTiebreak: Int,
             tiebreakStartServer: Player?,
             tiebreakFirstPointReceiver: Player?,
             lastTiebreakPointServer: Player?,
             isOnSecondServe: Bool = false,
             committedStatID: UUID? = nil,
             doublesServer: DoublesServer? = nil,
             doublesServiceIndex: Int = 0) {
            self.player = player
            self.action = action
            self.sets = sets
            self.currentPointsMe = currentPointsMe
            self.currentPointsOpponent = currentPointsOpponent
            self.currentServer = currentServer
            self.gameCount = gameCount
            self.pointCountInTiebreak = pointCountInTiebreak
            self.tiebreakStartServer = tiebreakStartServer
            self.tiebreakFirstPointReceiver = tiebreakFirstPointReceiver
            self.lastTiebreakPointServer = lastTiebreakPointServer
            self.isOnSecondServe = isOnSecondServe
            self.committedStatID = committedStatID
            self.doublesServer = doublesServer
            self.doublesServiceIndex = doublesServiceIndex
        }

        // Custom decoder so v1 saves (which lacked the v2 fields) decode
        // cleanly with sensible defaults.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            player = try c.decode(Player.self, forKey: .player)
            action = try c.decode(String.self, forKey: .action)
            sets = try c.decode([SetScore].self, forKey: .sets)
            currentPointsMe = try c.decode(Int.self, forKey: .currentPointsMe)
            currentPointsOpponent = try c.decode(Int.self, forKey: .currentPointsOpponent)
            currentServer = try c.decodeIfPresent(Player.self, forKey: .currentServer)
            gameCount = try c.decode(Int.self, forKey: .gameCount)
            pointCountInTiebreak = try c.decode(Int.self, forKey: .pointCountInTiebreak)
            tiebreakStartServer = try c.decodeIfPresent(Player.self, forKey: .tiebreakStartServer)
            tiebreakFirstPointReceiver = try c.decodeIfPresent(Player.self, forKey: .tiebreakFirstPointReceiver)
            lastTiebreakPointServer = try c.decodeIfPresent(Player.self, forKey: .lastTiebreakPointServer)
            isOnSecondServe = try c.decodeIfPresent(Bool.self, forKey: .isOnSecondServe) ?? false
            committedStatID = try c.decodeIfPresent(UUID.self, forKey: .committedStatID)
            doublesServer = try c.decodeIfPresent(DoublesServer.self, forKey: .doublesServer)
            doublesServiceIndex = try c.decodeIfPresent(Int.self, forKey: .doublesServiceIndex) ?? 0
        }
    }

    struct AppState: Codable {
        /// Bumped to 2 when the stats-tracking fields were added. v1 saves are
        /// migrated transparently by `loadState`.
        let version: Int
        let sets: [SetScore]
        let currentPointsMe: Int
        let currentPointsOpponent: Int
        let history: [HistoryEntry]
        let currentServer: Player?
        let gameCount: Int
        let pointCountInTiebreak: Int
        let tiebreakStartServer: Player?
        let tiebreakFirstPointReceiver: Player?
        let lastTiebreakPointServer: Player?

        // v2 fields — all default-able when migrating from v1.
        let currentMatchStats: [PointStat]
        let matchStartTime: Date?
        let isOnSecondServe: Bool
        let pendingStatPoint: PendingPointInfo?
        let currentMatchID: UUID?
        let matchElapsedSeconds: TimeInterval
        let setElapsedSeconds: [Int: TimeInterval]
        let pendingAnnouncementMessage: String?
        let pendingAnnouncementReason: String?
        // v3 fields — doubles support.
        let matchType: MatchType
        let doublesServer: DoublesServer?
        let doublesServiceOrder: [DoublesServer]
        let doublesServiceIndex: Int
        let tiebreakStartDoublesIndex: Int
        // v4 field — tiebreak-only match format.
        let matchFormat: MatchFormat
        // v5 field — deferred doubles team-server decision.
        let needsDoublesTeamServerDecision: Bool

        init(version: Int,
             sets: [SetScore],
             currentPointsMe: Int,
             currentPointsOpponent: Int,
             history: [HistoryEntry],
             currentServer: Player?,
             gameCount: Int,
             pointCountInTiebreak: Int,
             tiebreakStartServer: Player?,
             tiebreakFirstPointReceiver: Player?,
             lastTiebreakPointServer: Player?,
             currentMatchStats: [PointStat] = [],
             matchStartTime: Date? = nil,
             isOnSecondServe: Bool = false,
             pendingStatPoint: PendingPointInfo? = nil,
             currentMatchID: UUID? = nil,
             matchElapsedSeconds: TimeInterval = 0,
             setElapsedSeconds: [Int: TimeInterval] = [:],
             pendingAnnouncementMessage: String? = nil,
             pendingAnnouncementReason: String? = nil,
             matchType: MatchType = .singles,
             doublesServer: DoublesServer? = nil,
             doublesServiceOrder: [DoublesServer] = [],
             doublesServiceIndex: Int = 0,
             tiebreakStartDoublesIndex: Int = 0,
             matchFormat: MatchFormat = .standard,
             needsDoublesTeamServerDecision: Bool = false) {
            self.version = version
            self.sets = sets
            self.currentPointsMe = currentPointsMe
            self.currentPointsOpponent = currentPointsOpponent
            self.history = history
            self.currentServer = currentServer
            self.gameCount = gameCount
            self.pointCountInTiebreak = pointCountInTiebreak
            self.tiebreakStartServer = tiebreakStartServer
            self.tiebreakFirstPointReceiver = tiebreakFirstPointReceiver
            self.lastTiebreakPointServer = lastTiebreakPointServer
            self.currentMatchStats = currentMatchStats
            self.matchStartTime = matchStartTime
            self.isOnSecondServe = isOnSecondServe
            self.pendingStatPoint = pendingStatPoint
            self.currentMatchID = currentMatchID
            self.matchElapsedSeconds = matchElapsedSeconds
            self.setElapsedSeconds = setElapsedSeconds
            self.pendingAnnouncementMessage = pendingAnnouncementMessage
            self.pendingAnnouncementReason = pendingAnnouncementReason
            self.matchType = matchType
            self.doublesServer = doublesServer
            self.doublesServiceOrder = doublesServiceOrder
            self.doublesServiceIndex = doublesServiceIndex
            self.tiebreakStartDoublesIndex = tiebreakStartDoublesIndex
            self.matchFormat = matchFormat
            self.needsDoublesTeamServerDecision = needsDoublesTeamServerDecision
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version)
            sets = try c.decode([SetScore].self, forKey: .sets)
            currentPointsMe = try c.decode(Int.self, forKey: .currentPointsMe)
            currentPointsOpponent = try c.decode(Int.self, forKey: .currentPointsOpponent)
            history = try c.decode([HistoryEntry].self, forKey: .history)
            currentServer = try c.decodeIfPresent(Player.self, forKey: .currentServer)
            gameCount = try c.decode(Int.self, forKey: .gameCount)
            pointCountInTiebreak = try c.decode(Int.self, forKey: .pointCountInTiebreak)
            tiebreakStartServer = try c.decodeIfPresent(Player.self, forKey: .tiebreakStartServer)
            tiebreakFirstPointReceiver = try c.decodeIfPresent(Player.self, forKey: .tiebreakFirstPointReceiver)
            lastTiebreakPointServer = try c.decodeIfPresent(Player.self, forKey: .lastTiebreakPointServer)
            currentMatchStats = try c.decodeIfPresent([PointStat].self, forKey: .currentMatchStats) ?? []
            matchStartTime = try c.decodeIfPresent(Date.self, forKey: .matchStartTime)
            isOnSecondServe = try c.decodeIfPresent(Bool.self, forKey: .isOnSecondServe) ?? false
            pendingStatPoint = try c.decodeIfPresent(PendingPointInfo.self, forKey: .pendingStatPoint)
            currentMatchID = try c.decodeIfPresent(UUID.self, forKey: .currentMatchID)
            matchElapsedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .matchElapsedSeconds) ?? 0
            setElapsedSeconds = try c.decodeIfPresent([Int: TimeInterval].self, forKey: .setElapsedSeconds) ?? [:]
            pendingAnnouncementMessage = try c.decodeIfPresent(String.self, forKey: .pendingAnnouncementMessage)
            pendingAnnouncementReason = try c.decodeIfPresent(String.self, forKey: .pendingAnnouncementReason)
            matchType = try c.decodeIfPresent(MatchType.self, forKey: .matchType) ?? .singles
            doublesServer = try c.decodeIfPresent(DoublesServer.self, forKey: .doublesServer)
            doublesServiceOrder = try c.decodeIfPresent([DoublesServer].self, forKey: .doublesServiceOrder) ?? []
            doublesServiceIndex = try c.decodeIfPresent(Int.self, forKey: .doublesServiceIndex) ?? 0
            tiebreakStartDoublesIndex = try c.decodeIfPresent(Int.self, forKey: .tiebreakStartDoublesIndex) ?? 0
            matchFormat = try c.decodeIfPresent(MatchFormat.self, forKey: .matchFormat) ?? .standard
            needsDoublesTeamServerDecision = try c.decodeIfPresent(Bool.self, forKey: .needsDoublesTeamServerDecision) ?? false
        }
    }
    
    @Published var sets: [SetScore] = [SetScore()]
    @Published var currentPointsMe: Int = 0
    @Published var currentPointsOpponent: Int = 0

    /// True when the compass badge should be visible: at 0–0 of each regular
    /// game, or at every 6-point changeover boundary in a tiebreak (including
    /// the start). Returns false once the match is complete.
    var isAtGameStart: Bool {
        guard !isMatchComplete() else { return false }
        if sets.last?.isTieBreak == true {
            return pointCountInTiebreak % 6 == 0
        }
        return currentPointsMe == 0 && currentPointsOpponent == 0
    }

    /// Whether the sticky ends-switch reminder should replace the momentum
    /// strip: `nil` when it doesn't apply, `true`/`false` for switch/stay.
    /// Fixed-deuce-side formats (Perpetual Points) never change ends.
    /// Pure derivation of already-persisted state — see
    /// `docs/features/ENDS_SWITCH_REMINDER_PLAN.md` §7.2.
    var pendingEndsSwitchReminder: Bool? {
        guard !matchFormat.config.fixedDeuceSide else { return nil }
        return ScoringEngine.nextSetRequiresEndsSwitch(scoringState())
    }

    private(set) var history: [HistoryEntry] = []
    /// Momentum points inherited from the record snapshot at resume time.
    /// Merged with live history so the strip doesn't blank out after a resume.
    private var resumedRecentPoints: [Player] = []

    /// True when a live match has meaningful progress that should be protected
    /// before replacing/resuming another record.
    var hasInProgressMatchData: Bool {
        if !history.isEmpty || !currentMatchStats.isEmpty { return true }
        if currentPointsMe > 0 || currentPointsOpponent > 0 { return true }
        return sets.contains { $0.gamesMe > 0 || $0.gamesOpponent > 0 || $0.tieBreakPointsMe > 0 || $0.tieBreakPointsOpponent > 0 }
    }

    private let statsStore: StatsStoring

    private let stateFileURL: URL

    /// Backing store for the remembered match setup (`MatchSetupDefaults`
    /// keys) only — every other setting on this class still reads
    /// `UserDefaults.standard` directly at its `@Published` property
    /// initializer, which can't be redirected through an injected instance.
    /// Injectable (defaults to `.standard`) so tests can give each case its
    /// own isolated domain instead of racing the real one against whichever
    /// other test suite Swift Testing happens to run concurrently.
    private let userDefaults: UserDefaults

    init(statsStore: StatsStoring = StatsStore.shared, stateFileURL: URL? = nil, userDefaults: UserDefaults = .standard) {
        self.statsStore = statsStore
        self.stateFileURL = stateFileURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("appState.json")
        self.userDefaults = userDefaults
        if FileManager.default.fileExists(atPath: self.stateFileURL.path) {
            do {
                try BackupExcludedFileWriter.excludeFromBackup(at: self.stateFileURL)
            } catch {
                // Not surfaced in-app: the match data is intact, only its
                // backup exclusion is. `saveState` reapplies the flag on every
                // write, so this resolves itself on the next point.
                scoreStateLogger.error("Failed to exclude existing app state from backup: \(error.localizedDescription, privacy: .public)")
            }
        }

        // A store-level read/write failure means lost match data just as much as
        // a failed live-state save, so fold both into the same published health.
        if let reportingStore = statsStore as? PersistenceOutcomeReporting {
            reportingStore.onPersistenceOutcome = { [weak self] outcome in
                self?.applyPersistenceOutcome(outcome)
            }
        }
        UserDefaults.standard.register(defaults: [
            "statsTrackingEnabled": false
        ])

        statsTrackingEnabled = UserDefaults.standard.bool(forKey: "statsTrackingEnabled")
        detailedShotTrackingEnabled = statsTrackingEnabled

        // WorkoutManager is a plain stored property, not an @ObservedObject —
        // views that only observe `self` (e.g. the tracking strip) would never
        // redraw when `healthAccess` changes without this forward. Scoped to
        // just `$healthAccess` (not the manager's whole `objectWillChange`):
        // during a live match `currentHeartRate`/`totalKilocalories` publish
        // every 2–5 seconds, and forwarding those too would invalidate every
        // view observing the (large, widely-shared) view model on each tick —
        // HeartRateBadgeView already observes WorkoutManager directly for HR.
        // dropFirst() skips the initial replay of the current value on subscribe.
        workoutManager.$healthAccess
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Mirror phone-pushed Pulse Coach settings into the published values.
        NotificationCenter.default.addObserver(
            forName: .pulseCoachSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.refreshPulseCoachValuesFromDefaults()
        }
    }

    func beginMatchSession() {
        workoutManager.startWorkout(startDate: matchStartTime ?? Date())
    }

    /// Called after HealthKit authorization on launch. Restarts the workout
    /// session when the app was terminated mid-match and relaunched.
    func resumeWorkoutIfMatchInProgress() {
        guard sessionStartTime != nil, !isMatchComplete() else { return }
        workoutManager.startWorkout(startDate: matchStartTime ?? Date())
    }

    /// Resolved player max HR using the same precedence chain as the iPhone:
    /// manual override → 220 − age → 190.
    var resolvedMaxHR: Int {
        HRZone.resolveMaxHR(
            manualOverride: userMaxHROverride > 0 ? userMaxHROverride : nil,
            birthYear: userBirthYear > 0 ? userBirthYear : nil
        )
    }

    /// The three "what will this match record?" indicators — point tracking
    /// (format-aware), Health access, and Pulse Coach calibration — resolved
    /// once here so the start-screen strip and the settings summary can never
    /// disagree. Derivation itself lives in `MatchTrackingStatus` (Core,
    /// unit-tested). Always three; the strip collapses Pulse separately via
    /// `MatchTrackingStatus.collapsingPulseWhenHealthOff(_:)`.
    var trackingStatuses: [MatchTrackingStatus] {
        MatchTrackingStatus.all(
            matchFormat: matchFormat,
            pointTrackingEnabled: statsTrackingEnabled,
            healthAccess: workoutManager.healthAccess,
            birthYear: userBirthYear,
            maxHROverride: userMaxHROverride
        )
    }

    /// Called once the server is confirmed and the match is officially starting.
    /// Bootstraps the match identity (ID + timers) and pushes the initial
    /// in-progress record to the phone so it appears immediately without
    /// waiting for the first point.
    func syncMatchStart() {
        bootstrapLiveMatchIdentityIfNeeded()
        saveState()
    }

    /// Seeds state for a 10-point super-tiebreak-only match. Caller must have
    /// set `matchFormat = .superTiebreak`, `matchType`, and `currentServer`
    /// (and run `startDoublesMatch` for doubles) before invoking this.
    /// Replaces `sets` with a single tiebreak set and primes the tiebreak
    /// rotation off the chosen first server.
    func prepareTiebreakOnlySet() {
        guard isTiebreakOnlyFormat, let server = currentServer else { return }
        sets = [SetScore(isTieBreak: true)]
        currentPointsMe = 0
        currentPointsOpponent = 0
        pointCountInTiebreak = 0
        tiebreakStartServer = server
        tiebreakFirstPointReceiver = (server == .me) ? .opponent : .me
        lastTiebreakPointServer = nil
        if matchType == .doubles {
            tiebreakStartDoublesIndex = doublesServiceIndex
        }
        saveState()
    }

    /// Sets up a doubles match with the given first server and derives the full
    /// four-player service rotation. "S1" is whichever opponent serves first,
    /// "S2" the other — the labels are purely positional to avoid confusion.
    func startDoublesMatch(firstServer: DoublesServer) {
        matchType = .doubles
        doublesServiceIndex = 0
        needsDoublesTeamServerDecision = false
        switch firstServer {
        case .me:
            doublesServiceOrder = [.me, .opponentS1, .partner, .opponentS2]
        case .partner:
            doublesServiceOrder = [.partner, .opponentS1, .me, .opponentS2]
        case .opponentS1:
            // Provisional order — Me/Partner slot decided after game 1 via overlay.
            doublesServiceOrder = [.opponentS1, .me, .opponentS2, .partner]
            needsDoublesTeamServerDecision = true
        case .opponentS2:
            // Provisional order — Me/Partner slot decided after game 1 via overlay.
            doublesServiceOrder = [.opponentS2, .me, .opponentS1, .partner]
            needsDoublesTeamServerDecision = true
        }
        doublesServer = doublesServiceOrder[0]
        currentServer = firstServer.team
    }

    /// Called from the overlay after the opponent's first game to confirm
    /// which team member serves second, finalising the four-player rotation.
    func resolveDoublesTeamServer(_ server: DoublesServer) {
        guard needsDoublesTeamServerDecision else { return }
        needsDoublesTeamServerDecision = false
        // Rebuild the rotation so the chosen player is at index 1.
        if server == .partner, let firstServer = doublesServiceOrder.first {
            let otherOpponent: DoublesServer = (firstServer == .opponentS1) ? .opponentS2 : .opponentS1
            doublesServiceOrder = [firstServer, .partner, otherOpponent, .me]
        }
        // Advance to the next server (index 1) now that the decision is made.
        doublesServiceIndex = 1
        doublesServer = doublesServiceOrder[doublesServiceIndex]
        currentServer = doublesServer?.team ?? currentServer
        saveState()
    }

    // MARK: - Phone announcement helpers

    /// The name used in announcements for the user's side.
    private var myDisplayName: String { playerName.isEmpty ? "you" : playerName }

    /// Converts raw point counters to a spoken score string using umpire convention.
    /// Server's score is announced first; equal non-deuce scores use "X all".
    private func regularPointText(me: Int, opp: Int) -> String {
        let labels = ["Love", "Fifteen", "Thirty", "Forty"]
        if me >= 3 && opp >= 3 {
            if me == opp { return "Deuce" }
            return me > opp ? "Advantage \(myDisplayName)" : "Advantage Opponent"
        }
        let myLabel  = me  < labels.count ? labels[me]  : "\(me)"
        let oppLabel = opp < labels.count ? labels[opp] : "\(opp)"
        if me == opp { return "\(myLabel) all" }
        guard let server = currentServer else { return "\(myLabel) \(oppLabel)" }
        return server == .me ? "\(myLabel) \(oppLabel)" : "\(oppLabel) \(myLabel)"
    }

    /// Converts tiebreak point counters to a spoken score string (server's score first).
    /// Equal scores use "X all".
    private func tiebreakPointText(me: Int, opp: Int) -> String {
        if me == opp { return "\(wordForNumber(me)) all" }
        let server = lastTiebreakPointServer ?? currentServer
        if server == .me { return "\(me), \(opp)" }
        return "\(opp), \(me)"
    }

    /// Returns the spoken word for a game/set count (0 = "love", 1 = "one", …).
    private func wordForNumber(_ n: Int) -> String {
        switch n {
        case 0: return "love"; case 1: return "one"; case 2: return "two"
        case 3: return "three"; case 4: return "four"; case 5: return "five"
        case 6: return "six"; case 7: return "seven"
        default: return "\(n)"
        }
    }

    /// Returns spoken game-score text; uses "X all" when the game counts are equal.
    private func gameScoreText(gamesMe: Int, gamesOpp: Int) -> String {
        if gamesMe == gamesOpp { return "\(wordForNumber(gamesMe)) all" }
        return "\(wordForNumber(gamesMe)), \(wordForNumber(gamesOpp))"
    }

    private func showChangeover(symbol: String, reason: String, speechPhrase: String? = nil) {
        guard !isMatchComplete() else {
            pendingChangeoverAck = nil
            return
        }
        let info = ChangeoverInfo(symbol: symbol, reason: reason)

        let cleanPhrase = speechPhrase ?? reason
        if let existing = pendingPhoneAnnouncement {
            pendingPhoneAnnouncement = existing + " \(cleanPhrase)."
        } else {
            pendingPhoneAnnouncement = "\(cleanPhrase)."
        }

        if statsTrackingEnabled {
            pendingAnnouncementInfo = info
        } else {
            displayChangeover(info)
        }
    }

    private func displayChangeover(_ info: ChangeoverInfo) {
        pendingChangeoverAck = info
    }

    func acknowledgeChangeover() {
        pendingChangeoverAck = nil
    }

    /// True while a changeover popup is visible or about to appear (the brief
    /// delay after stats-sheet dismissal before the popup paints). Intentionally
    /// excludes `pendingAnnouncementInfo` — that flag tracks the queued info
    /// while the categorization sheet is up, which already blocks gestures via
    /// `pendingStatPoint`. Including it here used to freeze the UI when the
    /// sheet was dismissed without committing and the info was orphaned.
    var isChangeoverPending: Bool {
        pendingChangeoverAck != nil || pendingAnnouncementWorkItem != nil
    }

    /// Drops a queued changeover announcement that was waiting for the
    /// categorization sheet to commit. Used when the sheet is dismissed
    /// without a commit (outer match sheet pulled down, stats toggled off,
    /// match resumed from history), to keep `pendingAnnouncementInfo` and
    /// the work item from being orphaned.
    private func discardPendingAnnouncement() {
        pendingAnnouncementInfo = nil
        pendingAnnouncementWorkItem?.cancel()
        pendingAnnouncementWorkItem = nil
    }

    /// Called when SwiftUI dismisses the categorization sheet (the binding
    /// setter fires with false). After a normal commit, `commitPointStat`
    /// has already cleared `pendingStatPoint`/`pendingOutcome` and scheduled
    /// the changeover work item — touching them here is a no-op. The case
    /// we actually care about is an *auto-dismiss* (outer match sheet pulled
    /// down on watchOS): clear the queued announcement info so it doesn't
    /// survive as an invisible swipe blocker. The work item is left alone:
    /// in the auto-dismiss case it is already nil; in the commit case it
    /// must keep its scheduled fire so the changeover overlay still paints.
    func discardPendingStatCategorization() {
        pendingStatPoint = nil
        pendingOutcome = nil
        pendingAnnouncementInfo = nil
    }

    /// Clears every transient piece of pending UI state: categorization
    /// staging, the queued changeover info, and the scheduled work item.
    /// Used by paths that want a hard reset of the pending machinery
    /// (stats-tracking toggled off, match resumed from history). Not for
    /// the binding-setter path — see `discardPendingStatCategorization`
    /// for why the work item must survive a normal commit dismissal.
    private func discardAllPendingState() {
        discardPendingStatCategorization()
        discardPendingAnnouncement()
    }

    /// True when the receiver (non-server) can win the service game by winning
    /// this point. Excludes tiebreaks — no break points there.
    private func isCurrentPointBreakPoint() -> Bool {
        ScoringEngine.isCurrentPointBreakPoint(scoringState())
    }

    func winPoint(player: Player) {
        // Capture stats context BEFORE updateScore, since updateScore rotates
        // the server when a game completes.
        let serverBefore = currentServer
        let setIndexBefore = max(sets.count - 1, 0)
        let wasSecondServe = isOnSecondServe
        let wasBreakPoint = isCurrentPointBreakPoint()
        let scoreSnapshot = gameScoreSnapshotAtPointStart()

        history.append(
            HistoryEntry(
                player: player,
                action: "win",
                sets: sets,
                currentPointsMe: currentPointsMe,
                currentPointsOpponent: currentPointsOpponent,
                currentServer: currentServer,
                gameCount: gameCount,
                pointCountInTiebreak: pointCountInTiebreak,
                tiebreakStartServer: tiebreakStartServer,
                tiebreakFirstPointReceiver: tiebreakFirstPointReceiver,
                lastTiebreakPointServer: lastTiebreakPointServer,
                isOnSecondServe: wasSecondServe,
                committedStatID: nil,
                doublesServer: doublesServer,
                doublesServiceIndex: doublesServiceIndex
            )
        )
        updateScore(for: player)

        if serverBefore != nil {
            bootstrapLiveMatchIdentityIfNeeded()
        }

        if matchFormat.config.disablesPointTracking {
            // Perpetual Points format: no categorisation sheet, no auto stat —
            // just count the point. History entry above still supports undo.
        } else if statsTrackingEnabled, let server = serverBefore {
            let info = PendingPointInfo(
                server: server,
                winner: player,
                setIndex: setIndexBefore,
                isSecondServe: wasSecondServe,
                isBreakPoint: wasBreakPoint,
                gameScoreAtStart: scoreSnapshot
            )
            pendingStatPoint = info
        } else {
            // Stats off: silently record an uncategorized point for history/analytics.
            if let server = serverBefore {
                autoRecordPointStat(server: server, winner: player,
                                    setIndex: setIndexBefore,
                                    isSecondServe: wasSecondServe,
                                    isBreakPoint: wasBreakPoint,
                                    gameScoreAtStart: scoreSnapshot)
            }
        }
        isOnSecondServe = false
        saveState()
        syncHeadingMonitoring()
    }

    func losePoint(player: Player) {
        let opponent = player == .me ? ScoreViewModel.Player.opponent : ScoreViewModel.Player.me
        let serverBefore = currentServer
        let setIndexBefore = max(sets.count - 1, 0)
        let wasSecondServe = isOnSecondServe
        let wasBreakPoint = isCurrentPointBreakPoint()
        let scoreSnapshot = gameScoreSnapshotAtPointStart()

        history.append(
            HistoryEntry(
                player: opponent,
                action: "win",
                sets: sets,
                currentPointsMe: currentPointsMe,
                currentPointsOpponent: currentPointsOpponent,
                currentServer: currentServer,
                gameCount: gameCount,
                pointCountInTiebreak: pointCountInTiebreak,
                tiebreakStartServer: tiebreakStartServer,
                tiebreakFirstPointReceiver: tiebreakFirstPointReceiver,
                lastTiebreakPointServer: lastTiebreakPointServer,
                isOnSecondServe: wasSecondServe,
                committedStatID: nil,
                doublesServer: doublesServer,
                doublesServiceIndex: doublesServiceIndex
            )
        )
        updateScore(for: opponent)

        if serverBefore != nil {
            bootstrapLiveMatchIdentityIfNeeded()
        }

        if matchFormat.config.disablesPointTracking {
            // Perpetual Points format: skip categorisation entirely.
        } else if statsTrackingEnabled, let server = serverBefore {
            let info = PendingPointInfo(
                server: server,
                winner: opponent,
                setIndex: setIndexBefore,
                isSecondServe: wasSecondServe,
                isBreakPoint: wasBreakPoint,
                gameScoreAtStart: scoreSnapshot
            )
            pendingStatPoint = info
        } else {
            if let server = serverBefore {
                autoRecordPointStat(server: server, winner: opponent,
                                    setIndex: setIndexBefore,
                                    isSecondServe: wasSecondServe,
                                    isBreakPoint: wasBreakPoint,
                                    gameScoreAtStart: scoreSnapshot)
            }
        }
        isOnSecondServe = false
        saveState()
        syncHeadingMonitoring()
    }

    /// Snapshots the pre-point score from the server's perspective. Returns
    /// nil if there is no current server (shouldn't happen mid-match, but
    /// keeps this defensive).
    ///
    /// Regular games and tiebreaks use different running counters:
    /// `currentPointsMe/Opponent` for regular games, `sets.last.tieBreakPoints*`
    /// for tiebreaks. Reading the wrong pair during a tiebreak silently stores
    /// 0-0, so this helper branches on `isTieBreak`.
    private func gameScoreSnapshotAtPointStart() -> GameScoreSnapshot? {
        ScoringEngine.gameScoreSnapshotAtPointStart(scoringState())
    }

    func updateScore(for player: Player) {
        let result = ScoringEngine.pointWon(by: player, in: scoringState())
        applyScoringResult(result)
    }

    private func scoringState() -> ScoringState {
        ScoringState(
            sets: sets,
            currentPointsMe: currentPointsMe,
            currentPointsOpponent: currentPointsOpponent,
            currentServer: currentServer,
            gameCount: gameCount,
            pointCountInTiebreak: pointCountInTiebreak,
            tiebreakStartServer: tiebreakStartServer,
            tiebreakFirstPointReceiver: tiebreakFirstPointReceiver,
            lastTiebreakPointServer: lastTiebreakPointServer,
            matchType: matchType,
            matchFormat: matchFormat,
            doublesServer: doublesServer,
            doublesServiceOrder: doublesServiceOrder,
            doublesServiceIndex: doublesServiceIndex,
            tiebreakStartDoublesIndex: tiebreakStartDoublesIndex,
            needsDoublesTeamServerDecision: needsDoublesTeamServerDecision
        )
    }

    private func applyScoringResult(_ result: ScoringResult) {
        for event in result.events {
            switch event {
            case .setTimerSnapshot(let index):
                if let start = currentSetSessionStart {
                    setElapsedSeconds[index, default: 0] += Date().timeIntervalSince(start)
                }
            case .setTimerStarted:
                currentSetSessionStart = Date()
            case .setTimerStopped:
                currentSetSessionStart = nil
            default:
                break
            }
        }

        applyScoringState(result.state)

        for event in result.events {
            switch event {
            case .announcement(let announcement):
                pendingPhoneAnnouncement = text(for: announcement)
            case .changeover(let changeover):
                showChangeover(
                    symbol: changeover.symbol,
                    reason: text(for: changeover.reason),
                    speechPhrase: speechText(for: changeover.reason)
                )
            case .setTimerSnapshot, .setTimerStarted, .setTimerStopped:
                break
            }
        }
    }

    private func applyScoringState(_ state: ScoringState) {
        sets = state.sets
        currentPointsMe = state.currentPointsMe
        currentPointsOpponent = state.currentPointsOpponent
        currentServer = state.currentServer
        gameCount = state.gameCount
        pointCountInTiebreak = state.pointCountInTiebreak
        tiebreakStartServer = state.tiebreakStartServer
        tiebreakFirstPointReceiver = state.tiebreakFirstPointReceiver
        lastTiebreakPointServer = state.lastTiebreakPointServer
        matchType = state.matchType
        matchFormat = state.matchFormat
        doublesServer = state.doublesServer
        doublesServiceOrder = state.doublesServiceOrder
        doublesServiceIndex = state.doublesServiceIndex
        tiebreakStartDoublesIndex = state.tiebreakStartDoublesIndex
        needsDoublesTeamServerDecision = state.needsDoublesTeamServerDecision
    }

    private func text(for announcement: ScoringAnnouncement) -> String {
        switch announcement {
        case .regularPoint(let me, let opponent):
            return regularPointText(me: me, opp: opponent)
        case .tiebreakPoint(let me, let opponent, let lastServer):
            return tiebreakPointText(me: me, opp: opponent, server: lastServer)
        case .gameWon(let winner, let gamesMe, let gamesOpponent):
            let gameWinner = winner == .me ? myDisplayName : "Opponent"
            return "Game, \(gameWinner). \(gameScoreText(gamesMe: gamesMe, gamesOpp: gamesOpponent))."
        case .tiebreakStarted(let requiresTwoPointLead):
            return requiresTwoPointLead ? "Tiebreak." : "Sudden death point."
        case .setWon(let winner, let setsWonMe, let setsWonOpponent):
            let setWinner = winner == .me ? myDisplayName : "Opponent"
            let setsText = setsWonMe == setsWonOpponent
                ? "\(wordForNumber(setsWonMe)) all"
                : "\(wordForNumber(setsWonMe)), \(wordForNumber(setsWonOpponent))"
            return "Set, \(setWinner). \(setsText)."
        case .matchWon(let winner):
            let matchWinner = winner == .me ? myDisplayName : "Opponent"
            return "Game, set, and match, \(matchWinner)."
        }
    }

    private func text(for reason: ScoringChangeoverReason) -> String {
        switch reason {
        case .oddGames:
            return "Odd games – players change ends"
        case .evenGames:
            return "Even games – balls change ends"
        case .setCompletePlayers:
            return "Set complete – players change ends"
        case .setCompleteBalls:
            return "Set complete – balls change ends"
        case .setCompletePlayersAndBalls:
            return "Set complete – players & balls change ends"
        case .tiebreakSixPoints:
            return "Every 6 tiebreak points – players & balls change ends"
        case .tiebreakOddPoint:
            return "Odd tiebreak point – balls change ends"
        case .tiebreakBegins(let games):
            return "Games at \(games)-\(games) – tiebreak begins"
        case .suddenDeathBegins(let games):
            return "Games at \(games)-\(games) – sudden death point"
        }
    }

    private func speechText(for reason: ScoringChangeoverReason) -> String {
        switch reason {
        case .oddGames, .setCompletePlayers:
            return "Players change ends"
        case .evenGames, .setCompleteBalls, .tiebreakOddPoint:
            return "Balls change ends"
        case .setCompletePlayersAndBalls, .tiebreakSixPoints:
            return "Players and balls change ends"
        case .tiebreakBegins:
            return "Tiebreak begins"
        case .suddenDeathBegins:
            return "Sudden death point"
        }
    }

    private func tiebreakPointText(me: Int, opp: Int, server: Player?) -> String {
        if me == opp { return "\(wordForNumber(me)) all" }
        if server == .me { return "\(me), \(opp)" }
        return "\(opp), \(me)"
    }
    
    func clearHistory() {
        history.removeAll()
        resumedRecentPoints = []
    }

    /// Phase 1 of the two-step categorization sheet. The user picked an
    /// outcome; if detailed shot tracking is on AND the outcome is ambiguous
    /// about ending shot, stash the outcome and let the sheet advance to
    /// phase 2. Otherwise commit immediately (DF auto-locks ending shot to
    /// `.serve`; with detailed tracking off we just store nil).
    func selectOutcome(_ outcome: PointOutcome) {
        guard pendingStatPoint != nil else { return }
        if outcome == .doubleFault {
            commitPointStat(outcome: .doubleFault, endingShot: .serve)
            return
        }
        if detailedShotTrackingEnabled {
            pendingOutcome = outcome
        } else {
            commitPointStat(outcome: outcome, endingShot: nil)
        }
    }

    /// Phase 2 of the two-step sheet. Commits the previously stashed outcome
    /// with the user's chosen ending shot.
    func commitEndingShot(_ shot: EndingShot) {
        guard let outcome = pendingOutcome else { return }
        commitPointStat(outcome: outcome, endingShot: shot)
    }

    /// Back affordance on phase 2: drop the stashed outcome so the sheet
    /// re-renders phase 1. The score change is left intact; use `undo()` to
    /// roll the whole point back.
    func cancelOutcomeSelection() {
        pendingOutcome = nil
    }

    /// Back-compat overload used by existing tests that pre-date detailed
    /// shot tracking. Treats the call as "no ending shot recorded."
    func commitPointStat(outcome: PointOutcome) {
        commitPointStat(outcome: outcome, endingShot: nil)
    }

    /// Commits the user's chosen outcome (and optional ending shot) for the
    /// most recently scored point. Appends a `PointStat`, stamps its id onto
    /// the most recent `HistoryEntry` so undo can locate it, and resets the
    /// second-serve flag for the next point.
    func commitPointStat(outcome: PointOutcome, endingShot: EndingShot?) {
        guard let pending = pendingStatPoint else { return }
        let stat = PointStat(
            setIndex: pending.setIndex,
            server: pending.server,
            winner: pending.winner,
            outcome: outcome,
            isSecondServe: pending.isSecondServe,
            isBreakPoint: pending.isBreakPoint,
            endingShot: detailedShotTrackingEnabled ? endingShot : nil,
            gameScoreAtStart: pending.gameScoreAtStart,
            heartRateBPM: currentHeartRateForStat(),
            stepsCumulative: currentStepsForStat()
        )
        currentMatchStats.append(stat)
        stampStatID(stat.id)
        pendingStatPoint = nil
        pendingOutcome = nil
        isOnSecondServe = false
        if let info = pendingAnnouncementInfo {
            pendingAnnouncementInfo = nil
            // Delay so the sheet dismissal animation finishes before the
            // changeover popup appears on ContentView. Store the work item
            // so undo/reset can cancel it if state changes during the window.
            let work = DispatchWorkItem { [weak self] in
                self?.pendingAnnouncementWorkItem = nil
                self?.displayChangeover(info)
            }
            pendingAnnouncementWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
        saveState()
    }

    /// Toggles the second-serve flag for the next-to-be-scored point. Driven
    /// by the double-tap gesture on the score display. No-op while a
    /// categorization is pending or when stats tracking is off.
    func toggleSecondServe() {
        guard statsTrackingEnabled,
              !matchFormat.config.disablesPointTracking,
              currentServer != nil,
              pendingStatPoint == nil,
              !isMatchComplete() else { return }
        isOnSecondServe.toggle()
        if isOnSecondServe {
            pendingPhoneAnnouncement = "Second serve."
        }
        saveState()
    }

    /// Silently creates and appends an uncategorized PointStat when point
    /// outcome tracking is OFF. Captures all automatically-available fields;
    /// `outcome` is set to `.uncategorized` and `endingShot` to nil.
    /// Stamps `committedStatID` on the most recent history entry so `undo()`
    /// can remove it precisely — identical pattern to `commitPointStat`.
    private func autoRecordPointStat(
        server: Player, winner: Player, setIndex: Int,
        isSecondServe: Bool, isBreakPoint: Bool,
        gameScoreAtStart: GameScoreSnapshot?
    ) {
        let stat = PointStat(
            setIndex: setIndex,
            server: server,
            winner: winner,
            outcome: .uncategorized,
            isSecondServe: isSecondServe,
            isBreakPoint: isBreakPoint,
            endingShot: nil,
            gameScoreAtStart: gameScoreAtStart,
            heartRateBPM: currentHeartRateForStat(),
            stepsCumulative: currentStepsForStat()
        )
        currentMatchStats.append(stat)
        stampStatID(stat.id)
    }

    /// Snapshots the current live heart rate as an integer for stamping onto a
    /// `PointStat`. Returns `nil` when the workout session is off or the sensor
    /// has not yet reported a sample.
    private func currentHeartRateForStat() -> Int? {
        guard let bpm = workoutManager.currentHeartRate, bpm > 0 else { return nil }
        return Int(bpm.rounded())
    }

    /// Snapshots the cumulative step count from the live workout builder.
    /// Returns `nil` when no workout session is active or before HealthKit has
    /// produced any step samples for the current match.
    private func currentStepsForStat() -> Int? {
        guard workoutManager.isRunning else { return nil }
        return workoutManager.currentTotalStepsForStat()
    }

    /// Stamps a committed stat's ID onto the most recent history entry so
    /// `undo()` can remove it precisely by ID rather than by position.
    private func stampStatID(_ statID: UUID) {
        guard let last = history.last else { return }
        history[history.count - 1] = HistoryEntry(
            player: last.player,
            action: last.action,
            sets: last.sets,
            currentPointsMe: last.currentPointsMe,
            currentPointsOpponent: last.currentPointsOpponent,
            currentServer: last.currentServer,
            gameCount: last.gameCount,
            pointCountInTiebreak: last.pointCountInTiebreak,
            tiebreakStartServer: last.tiebreakStartServer,
            tiebreakFirstPointReceiver: last.tiebreakFirstPointReceiver,
            lastTiebreakPointServer: last.lastTiebreakPointServer,
            isOnSecondServe: last.isOnSecondServe,
            committedStatID: statID,
            doublesServer: last.doublesServer,
            doublesServiceIndex: last.doublesServiceIndex
        )
    }

    /// Persists the in-progress match into StatsStore (or removes it from
    /// StatsStore if it has no stats). Returns true if a record was written.
    @discardableResult
    private func finalizeCurrentMatchToStore() -> Bool {
        guard let start = matchStartTime,
              let id = currentMatchID,
              hasInProgressMatchData else {
            return false
        }
        // Only count fully-completed sets toward the winner — an in-progress
        // set where one player is merely ahead must not flip the match to
        // "completed", or the resume flow would break for that record.
        // Perpetual tiebreak: determine winner by counting completed tiebreaks
        // won by each side. If equal, the player leading the current in-progress
        // tiebreak wins. This replaces the old sentinel of always writing false.
        let iWon: Bool?
        if matchFormat.config.isEndless {
            let completedTBs = sets.filter {
                $0.isTieBreak && ScoringEngine.isTiebreakComplete(
                    mePoints: $0.tieBreakPointsMe,
                    oppPoints: $0.tieBreakPointsOpponent,
                    target: 10,
                    format: matchFormat
                )
            }
            let winsMe  = completedTBs.filter { $0.tieBreakPointsMe  > $0.tieBreakPointsOpponent }.count
            let winsOpp = completedTBs.filter { $0.tieBreakPointsOpponent > $0.tieBreakPointsMe  }.count
            if winsMe > winsOpp {
                iWon = true
            } else if winsOpp > winsMe {
                iWon = false
            } else {
                // Equal completed tiebreaks: check who leads the current in-progress set.
                // Sum tiebreak and regular-game point counters — they are mutually exclusive
                // (only one pair is non-zero depending on isTieBreak state).
                let current = sets.last
                let mePoints  = (current?.tieBreakPointsMe  ?? 0) + currentPointsMe
                let oppPoints = (current?.tieBreakPointsOpponent ?? 0) + currentPointsOpponent
                if mePoints > oppPoints {
                    iWon = true
                } else if oppPoints > mePoints {
                    iWon = false
                } else {
                    iWon = nil
                }
            }
        } else {
            iWon = matchWinner().map { $0 == .me }
        }
        let totalElapsed = matchElapsedSeconds + (sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0)
        var finalSetElapsed = setElapsedSeconds
        let currentSetIndex = max(sets.count - 1, 0)
        if let setStart = currentSetSessionStart {
            finalSetElapsed[currentSetIndex, default: 0] += Date().timeIntervalSince(setStart)
        }
        let hkSnapshot = workoutManager.snapshotActivity()
        let record = MatchRecord(
            id: id,
            startTime: start,
            endTime: (iWon != nil || matchFormat.config.isEndless) ? Date() : nil,
            setScores: sets,
            stats: currentMatchStats,
            iWon: iWon,
            currentPointsMe: currentPointsMe,
            currentPointsOpponent: currentPointsOpponent,
            currentServer: currentServer,
            gameCount: gameCount,
            pointCountInTiebreak: pointCountInTiebreak,
            tiebreakStartServer: tiebreakStartServer,
            tiebreakFirstPointReceiver: tiebreakFirstPointReceiver,
            lastTiebreakPointServer: lastTiebreakPointServer,
            isOnSecondServe: isOnSecondServe,
            matchType: matchType,
            matchFormat: matchFormat,
            doublesServer: doublesServer,
            doublesServiceOrder: doublesServiceOrder,
            doublesServiceIndex: doublesServiceIndex,
            tiebreakStartDoublesIndex: tiebreakStartDoublesIndex,
            matchElapsedSeconds: totalElapsed,
            setElapsedSeconds: finalSetElapsed,
            totalSteps: hkSnapshot?.steps,
            totalDistanceMeters: hkSnapshot?.distanceMeters,
            totalCaloriesKcal: hkSnapshot?.caloriesKcal
        )
        // Belt-and-braces: if this append will evict the oldest watch record,
        // push the full history first so the phone archives the about-to-be-
        // dropped record even if the per-match push hasn't arrived yet.
        if let sync = syncService {
            let history = statsStore.loadHistory()
            if history.count >= StatsStore.historyCap {
                sync.sendFullHistory(history)
            }
        }
        statsStore.appendMatch(record)
        syncService?.sendMatch(record, announcement: nil)
        return true
    }

    /// Seeds the next match's setup from the remembered pair. No-op while a
    /// match is live or mid-restore, so resuming a Super Tiebreak is never
    /// rewritten to Best of 3. Called at the tail of `loadState()` and
    /// `resetMatch()` — never in `init`, which runs before either restore path
    /// and would just be overwritten (see docs/features/MATCH_START_UX_PLAN.md §5.4).
    private func applyRememberedSetupIfIdle() {
        guard currentServer == nil, currentMatchStats.isEmpty, history.isEmpty else { return }
        let defaults = MatchSetupDefaults.resolve(
            formatRaw: userDefaults.string(forKey: MatchSetupDefaults.formatKey),
            typeRaw: userDefaults.string(forKey: MatchSetupDefaults.typeKey))
        matchFormat = defaults.format
        matchType = defaults.type
    }

    /// Remembers the just-committed match setup so the next match on the start
    /// screen defaults to it. Called from `commitServerSelection()` — the point
    /// both the singles and doubles setup paths funnel through.
    func persistMatchSetupDefaults() {
        userDefaults.set(matchFormat.rawValue, forKey: MatchSetupDefaults.formatKey)
        userDefaults.set(matchType.rawValue, forKey: MatchSetupDefaults.typeKey)
    }

    func resetMatch() {
        workoutManager.stopWorkout()
        finalizeCurrentMatchToStore()
        syncService?.clearActiveMatch()
        currentServer = nil
        gameCount = 0
        pointCountInTiebreak = 0
        tiebreakStartServer = nil
        tiebreakFirstPointReceiver = nil
        lastTiebreakPointServer = nil
        pendingChangeoverAck = nil
        sets = [SetScore(isTieBreak: false)]
        currentPointsMe = 0
        currentPointsOpponent = 0
        currentMatchStats = []
        matchStartTime = nil
        pendingStatPoint = nil
        pendingOutcome = nil
        pendingAnnouncementInfo = nil
        pendingAnnouncementWorkItem?.cancel()
        pendingAnnouncementWorkItem = nil
        isOnSecondServe = false
        currentMatchID = nil
        matchElapsedSeconds = 0
        setElapsedSeconds = [:]
        currentSetSessionStart = nil
        sessionStartTime = nil
        shouldOpenMatchView = false
        matchType = .singles
        matchFormat = .standard
        doublesServer = nil
        needsDoublesTeamServerDecision = false
        doublesServiceOrder = []
        doublesServiceIndex = 0
        tiebreakStartDoublesIndex = 0
        clearHistory()
        resetHeadingState()
        // The guard is a no-op here — the match has just ended, so the idle
        // triple predicate already holds — but routing through the same
        // helper keeps one rule for "seed from the remembered setup."
        applyRememberedSetupIfIdle()
        saveState()
    }

    func startHeadingMonitoring() {
        guard checkChangeover else { return }
        // Fixed-deuce-side formats (Perpetual Points) suppress the compass
        // entirely and never change ends, so there is nothing for the heading
        // sensor to drive.
        guard !matchFormat.config.fixedDeuceSide else { return }
        guard CLLocationManager.headingAvailable() else { return }
        if headingManager != nil { return }
        let mgr = HeadingManager()
        headingManager = mgr
        mgr.onHeading = { [weak self] heading in
            DispatchQueue.main.async {
                self?.currentDeviceHeading = heading.magneticHeading
                self?.currentHeadingAccuracy = heading.headingAccuracy
            }
        }
        mgr.start()
    }

    func lockInitialHeading() {
        guard let current = currentDeviceHeading else { return }
        courtInitialHeading = current
        headingManager?.lock()
    }

    func pauseHeadingMonitoring() {
        headingManager?.stop()
        headingManager = nil
    }

    /// Starts or stops heading monitoring to match the current game state.
    /// Heading is only needed at the start of each game (before the first point),
    /// so this keeps the CLLocationManager idle during play to save battery.
    func syncHeadingMonitoring() {
        guard checkChangeover else { return }
        // Fixed-deuce-side formats keep the sensor parked — isAtGameStart
        // ticks back to true at every 6-point tiebreak boundary, which would
        // otherwise restart CLLocationManager with nothing to display.
        if matchFormat.config.fixedDeuceSide {
            pauseHeadingMonitoring()
            return
        }
        if isAtGameStart {
            startHeadingMonitoring()
        } else {
            pauseHeadingMonitoring()
        }
    }

    func resetHeadingState() {
        pauseHeadingMonitoring()
        UserDefaults.standard.removeObject(forKey: "courtInitialHeading")
        courtInitialHeading = nil
        currentDeviceHeading = nil
        currentHeadingAccuracy = -1
    }

    /// Restores a previously parked in-progress (or completed) match as the
    /// live match. Caller is responsible for confirming with the user if a
    /// different live match already exists. Removes the record from StatsStore
    /// because it'll be re-appended on the next finalize.
    func resumeMatch(_ record: MatchRecord) {
        // If a different live match exists, park it first so it's not lost.
        if let liveID = currentMatchID, liveID != record.id, hasInProgressMatchData {
            finalizeCurrentMatchToStore()
        }
        sets = record.setScores
        currentPointsMe = record.currentPointsMe
        currentPointsOpponent = record.currentPointsOpponent
        currentServer = record.currentServer
        gameCount = record.gameCount
        pointCountInTiebreak = record.pointCountInTiebreak
        tiebreakStartServer = record.tiebreakStartServer
        tiebreakFirstPointReceiver = record.tiebreakFirstPointReceiver
        lastTiebreakPointServer = record.lastTiebreakPointServer
        matchType = record.matchType
        matchFormat = record.matchFormat
        doublesServer = record.doublesServer
        doublesServiceOrder = record.doublesServiceOrder
        doublesServiceIndex = record.doublesServiceIndex
        tiebreakStartDoublesIndex = record.tiebreakStartDoublesIndex
        currentMatchStats = record.stats
        matchStartTime = record.startTime
        currentMatchID = record.id
        // Resume does not preserve the per-point HistoryEntry chain — undo
        // therefore only works for points scored after the resume. This is an
        // accepted v1 limitation since we don't persist `history` in
        // MatchRecord. We do seed resumedRecentPoints from the record so the
        // momentum strip stays populated until live history pushes it out.
        history = []
        resumedRecentPoints = record.recentPoints
        discardAllPendingState()
        // Restore the persisted second-serve flag so the next point is
        // correctly classified after resume.
        isOnSecondServe = record.isOnSecondServe
        applyDoublesDefaultsIfNeeded()
        pendingChangeoverAck = nil
        // Restore accumulated play time and begin a new session clock.
        matchElapsedSeconds = record.matchElapsedSeconds
        setElapsedSeconds = record.setElapsedSeconds
        sessionStartTime = Date()
        currentSetSessionStart = Date()
        workoutManager.stopWorkout()
        workoutManager.startWorkout(startDate: matchStartTime ?? Date())
        // Signal HomeView to navigate to the score view.
        shouldOpenMatchView = true
        // Drop from store; will be re-appended on next finalize.
        statsStore.removeMatch(id: record.id)
        saveState()
    }
    

    /// Ensures every played match gets a stable identity/timer anchor, even
    /// when detailed point stats are disabled.
    private func bootstrapLiveMatchIdentityIfNeeded() {
        let now = Date()
        if matchStartTime == nil { matchStartTime = now }
        if currentMatchID == nil { currentMatchID = UUID() }
        // sessionStartTime is only set on resume/restore; bootstrap it here so that
        // fresh single-session matches accumulate correct total elapsed time.
        if sessionStartTime == nil { sessionStartTime = now }
        // Only start the set timer for an in-progress match. The scoring
        // reducer stops the set timer for the match-winning set so finalize
        // does not accumulate idle time after the match ends.
        if currentSetSessionStart == nil && !isMatchComplete() {
            currentSetSessionStart = sessionStartTime
        }
    }

    func saveState() {
        let snapshotElapsed = matchElapsedSeconds + (sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0)
        var snapshotSetElapsed = setElapsedSeconds
        let currentSetIndex = max(sets.count - 1, 0)
        if let start = currentSetSessionStart {
            snapshotSetElapsed[currentSetIndex, default: 0] += Date().timeIntervalSince(start)
        }
        let state = AppState(
            version: 5,
            sets: sets,
            currentPointsMe: currentPointsMe,
            currentPointsOpponent: currentPointsOpponent,
            history: history,
            currentServer: currentServer,
            gameCount: gameCount,
            pointCountInTiebreak: pointCountInTiebreak,
            tiebreakStartServer: tiebreakStartServer,
            tiebreakFirstPointReceiver: tiebreakFirstPointReceiver,
            lastTiebreakPointServer: lastTiebreakPointServer,
            currentMatchStats: currentMatchStats,
            matchStartTime: matchStartTime,
            isOnSecondServe: isOnSecondServe,
            pendingStatPoint: pendingStatPoint,
            currentMatchID: currentMatchID,
            matchElapsedSeconds: snapshotElapsed,
            setElapsedSeconds: snapshotSetElapsed,
            pendingAnnouncementMessage: (pendingAnnouncementInfo ?? pendingChangeoverAck)?.symbol,
            pendingAnnouncementReason: (pendingAnnouncementInfo ?? pendingChangeoverAck)?.reason,
            matchType: matchType,
            doublesServer: doublesServer,
            doublesServiceOrder: doublesServiceOrder,
            doublesServiceIndex: doublesServiceIndex,
            tiebreakStartDoublesIndex: tiebreakStartDoublesIndex,
            matchFormat: matchFormat,
            needsDoublesTeamServerDecision: needsDoublesTeamServerDecision
        )
        do {
            // Class B (until-first-unlock): the live-match state must stay writable
            // when the watch is locked/off-wrist during a match. The transient
            // Health-bearing state is excluded from device backup after every save.
            try BackupExcludedFileWriter.write(state, to: stateFileURL)
            applyPersistenceOutcome(.succeeded(.saveLiveMatch))
        } catch {
            // A dropped save is lost match data, so this reaches the log *and*
            // the start screen — a `#if DEBUG print` was invisible in release.
            scoreStateLogger.error("Failed to save live match state: \(error.localizedDescription, privacy: .public)")
            applyPersistenceOutcome(.failed(PersistenceFailure(
                operation: .saveLiveMatch,
                detail: error.localizedDescription
            )))
        }

        // Push in-progress checkpoint to the phone via WatchConnectivity so
        // the phone's archive stays current even if the match is never finished.
        if let sync = syncService, let start = matchStartTime, let id = currentMatchID {
            let checkpoint = MatchRecord(
                id: id,
                startTime: start,
                endTime: nil,
                setScores: sets,
                stats: currentMatchStats,
                iWon: nil,
                currentPointsMe: currentPointsMe,
                currentPointsOpponent: currentPointsOpponent,
                currentServer: currentServer,
                gameCount: gameCount,
                pointCountInTiebreak: pointCountInTiebreak,
                tiebreakStartServer: tiebreakStartServer,
                tiebreakFirstPointReceiver: tiebreakFirstPointReceiver,
                lastTiebreakPointServer: lastTiebreakPointServer,
                isOnSecondServe: isOnSecondServe,
                matchType: matchType,
                matchFormat: matchFormat,
                doublesServer: doublesServer,
                doublesServiceOrder: doublesServiceOrder,
                doublesServiceIndex: doublesServiceIndex,
                tiebreakStartDoublesIndex: tiebreakStartDoublesIndex,
                matchElapsedSeconds: snapshotElapsed,
                setElapsedSeconds: snapshotSetElapsed,
                recentPoints: Array((resumedRecentPoints + history.map { $0.player }).suffix(8)),
                momentumEnabled: momentumEnabled
            )
            let ann = phoneAnnouncementsEnabled ? pendingPhoneAnnouncement : nil
            pendingPhoneAnnouncement = nil
            sync.sendMatch(checkpoint, announcement: ann)
        } else {
            pendingPhoneAnnouncement = nil
        }
    }

    /// Fold a persistence outcome into `persistenceHealth`, publishing only
    /// when the displayed warning actually changes (saves run on every point).
    private func applyPersistenceOutcome(_ outcome: PersistenceOutcome) {
        var updated = persistenceHealth
        guard updated.apply(outcome) else { return }
        persistenceHealth = updated
    }

    /// Where an unreadable live-state file is kept when a restore fails, so the
    /// interrupted match survives the reset-and-save-over that follows.
    var unreadableStateFileURL: URL { stateFileURL.appendingPathExtension("unreadable") }

    /// Move a live-state file that could not be read or decoded out of the way.
    /// Without this the reset in `loadState()`'s catch is immediately followed by
    /// a `saveState()` that replaces the file — destroying the bytes a future
    /// migration or a support request could have recovered the match from. Only
    /// one quarantined copy is kept: the previous one is already unreadable, and
    /// the state file holds a single in-progress match.
    ///
    /// Best effort — the app must still start — but a failure is logged, because
    /// it means the unreadable file is still in place and will be overwritten.
    /// The state file carries Health-derived data and is excluded from device
    /// backup (reasserted in `init`); a rename preserves that exclusion, and it
    /// is reasserted on the quarantined copy regardless.
    private func quarantineUnreadableState() {
        let aside = unreadableStateFileURL
        do {
            if FileManager.default.fileExists(atPath: aside.path) {
                try FileManager.default.removeItem(at: aside)
            }
            try FileManager.default.moveItem(at: stateFileURL, to: aside)
            try BackupExcludedFileWriter.excludeFromBackup(at: aside)
        } catch {
            scoreStateLogger.error("Failed to set aside unreadable live match state: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Dismiss the persistence warning banner. The next failure re-raises it.
    func acknowledgePersistenceWarning() {
        guard persistenceHealth.failure != nil else { return }
        var updated = persistenceHealth
        updated.acknowledge()
        persistenceHealth = updated
    }

    func loadState() {
        // A missing file is a normal cold start; a file that exists but can't be
        // read is a real failure. The catch path below resets in-memory state, so
        // the unreadable file is set aside first — otherwise the next `saveState()`
        // (one point later) overwrites the only copy of the interrupted match.
        let hadSavedState = FileManager.default.fileExists(atPath: stateFileURL.path)
        do {
            let data = try Data(contentsOf: stateFileURL)
            let state = try JSONDecoder().decode(AppState.self, from: data)
            sets = state.sets
            currentPointsMe = state.currentPointsMe
            currentPointsOpponent = state.currentPointsOpponent
            history = state.history
            currentServer = state.currentServer
            gameCount = state.gameCount
            pointCountInTiebreak = state.pointCountInTiebreak
            tiebreakStartServer = state.tiebreakStartServer
            tiebreakFirstPointReceiver = state.tiebreakFirstPointReceiver
            lastTiebreakPointServer = state.lastTiebreakPointServer
            currentMatchStats = state.currentMatchStats
            matchStartTime = state.matchStartTime
            isOnSecondServe = state.isOnSecondServe
            pendingStatPoint = state.pendingStatPoint
            currentMatchID = state.currentMatchID
            matchElapsedSeconds = state.matchElapsedSeconds
            setElapsedSeconds = state.setElapsedSeconds
            if let symbol = state.pendingAnnouncementMessage {
                let info = ChangeoverInfo(symbol: symbol, reason: state.pendingAnnouncementReason ?? "")
                if state.pendingStatPoint != nil {
                    pendingAnnouncementInfo = info
                } else {
                    pendingChangeoverAck = info
                }
            }
            matchType = state.matchType
            doublesServer = state.doublesServer
            needsDoublesTeamServerDecision = state.needsDoublesTeamServerDecision
            doublesServiceOrder = state.doublesServiceOrder
            doublesServiceIndex = state.doublesServiceIndex
            tiebreakStartDoublesIndex = state.tiebreakStartDoublesIndex
            matchFormat = state.matchFormat
            applyDoublesDefaultsIfNeeded()
            if currentServer != nil || !currentMatchStats.isEmpty {
                sessionStartTime = Date()
                // Don't restart the set timer for a completed match; the final set's
                // elapsed is already finalized and must not accumulate idle time.
                if !isMatchComplete() {
                    currentSetSessionStart = Date()
                }
            }
            applyPersistenceOutcome(.succeeded(.restoreLiveMatch))
        } catch {
            if hadSavedState {
                scoreStateLogger.error("Failed to load previous live match state: \(error.localizedDescription, privacy: .public)")
                quarantineUnreadableState()
                applyPersistenceOutcome(.failed(PersistenceFailure(
                    operation: .restoreLiveMatch,
                    detail: error.localizedDescription
                )))
            }
            sets = [SetScore()]
            currentPointsMe = 0
            currentPointsOpponent = 0
            history = []
            currentServer = nil
            gameCount = 0
            pointCountInTiebreak = 0
            tiebreakStartServer = nil
            tiebreakFirstPointReceiver = nil
            lastTiebreakPointServer = nil
            currentMatchStats = []
            matchStartTime = nil
            isOnSecondServe = false
            pendingStatPoint = nil
            pendingOutcome = nil
            currentMatchID = nil
            matchType = .singles
            matchFormat = .standard
            doublesServer = nil
            doublesServiceOrder = []
            doublesServiceIndex = 0
            tiebreakStartDoublesIndex = 0
        }
        // Covers both exits above: a restored live match leaves the idle
        // guard false and is left untouched; anything else (including the
        // catch path's hard-coded fallback) is seeded from the remembered pair.
        applyRememberedSetupIfIdle()
    }

    func displayedScore(for player: Player) -> String {
        if isMatchComplete() {
            return matchWinner() == .me ? "You Won!" : "Opponent Won!"
        }
        
        if let lastSet = sets.last, lastSet.isTieBreak {
            return player == .me ? "\(lastSet.tieBreakPointsMe)" : "\(lastSet.tieBreakPointsOpponent)"
        }
        
        let scoreMap = ["0", "15", "30", "40", "AD"]
        let p1 = currentPointsMe
        let p2 = currentPointsOpponent
        
        if p1 >= 3 && p2 >= 3 {
            if p1 == p2 {
                return "40"
            } else if p1 > p2 {
                return player == .me ? "AD" : "40"
            } else {
                return player == .opponent ? "AD" : "40"
            }
        }
        
        let points = player == .me ? p1 : p2
        return scoreMap[min(points, 4)]
    }
    
    /// Returns only fully-completed sets from the given list. Shared by
    /// `isMatchComplete()` and `finalizeCurrentMatchToStore()` so both use
    /// the same definition of "completed" — preventing in-progress sets where
    /// one player is merely ahead from being counted as won.
    func completedSets(in setList: [SetScore]) -> [SetScore] {
        ScoringEngine.completedSets(in: ScoringState(
            sets: setList,
            matchFormat: matchFormat
        ))
    }

    func isMatchComplete() -> Bool {
        ScoringEngine.isMatchComplete(scoringState())
    }

    /// Returns the winner once the match is complete.
    func matchWinner() -> Player? {
        ScoringEngine.matchWinner(scoringState())
    }
    
    
    func undo() {
        guard let last = history.popLast() else { return }

        sets = last.sets
        currentPointsMe = last.currentPointsMe
        currentPointsOpponent = last.currentPointsOpponent
        currentServer = last.currentServer
        gameCount = last.gameCount
        pointCountInTiebreak = last.pointCountInTiebreak

        tiebreakStartServer = last.tiebreakStartServer
        tiebreakFirstPointReceiver = last.tiebreakFirstPointReceiver
        lastTiebreakPointServer = last.lastTiebreakPointServer

        // Stats undo: dismiss any open categorization sheet (both phase-1 and
        // phase-2) and remove the committed stat (if any).
        pendingStatPoint = nil
        pendingOutcome = nil
        pendingAnnouncementInfo = nil
        pendingAnnouncementWorkItem?.cancel()
        pendingAnnouncementWorkItem = nil
        if let statID = last.committedStatID {
            currentMatchStats.removeAll { $0.id == statID }
        }
        // Restore the second-serve state of the prior point.
        isOnSecondServe = last.isOnSecondServe
        doublesServer = last.doublesServer
        doublesServiceIndex = last.doublesServiceIndex

        pendingChangeoverAck = nil
        saveState()
        syncHeadingMonitoring()
    }

    var lastScoredPlayer: Player? {
        history.last?.player
    }

    func visibleSets() -> [SetScore] {
        return sets
    }

    private func applyDoublesDefaultsIfNeeded() {
        if matchType == .singles {
            doublesServer = nil
            doublesServiceOrder = []
            doublesServiceIndex = 0
            tiebreakStartDoublesIndex = 0
            return
        }
        if doublesServiceOrder.isEmpty {
            if let server = doublesServer {
                doublesServiceOrder = [server]
            }
            doublesServiceIndex = 0
            tiebreakStartDoublesIndex = 0
            return
        }
        doublesServiceIndex = max(0, min(doublesServiceIndex, doublesServiceOrder.count - 1))
        tiebreakStartDoublesIndex = max(0, min(tiebreakStartDoublesIndex, doublesServiceOrder.count - 1))
        if doublesServer == nil {
            doublesServer = doublesServiceOrder[doublesServiceIndex]
        }
    }

    func totalElapsedSeconds(at date: Date = Date()) -> TimeInterval {
        matchElapsedSeconds + (sessionStartTime.map { date.timeIntervalSince($0) } ?? 0)
    }
}

private class HeadingManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var isUpdating = false
    /// Tracks whether the court bearing has been confirmed by the user.
    /// Controls both the heading filter rate and calibration popup behaviour.
    private var isLocked = false
    var onHeading: ((CLHeading) -> Void)?

    // Named constants for the two operating modes.
    // preciseFilter: tight enough for the pre-lock confirmation screen.
    // relaxedFilter: sufficient for the ±45° green-zone badge during play.
    private static let preciseFilter: CLLocationDegrees = 10
    private static let relaxedFilter: CLLocationDegrees = 20

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard !isUpdating else { return }
        // If restarting after a resume with the bearing already locked, use the
        // relaxed filter immediately rather than resetting to precise rate.
        manager.headingFilter = isLocked ? Self.relaxedFilter : Self.preciseFilter
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingHeading()
            isUpdating = true
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    /// Called once the court bearing is confirmed. Relaxes the update rate and
    /// suppresses future calibration popups.
    func lock() {
        isLocked = true
        manager.headingFilter = Self.relaxedFilter
    }

    func stop() {
        manager.stopUpdatingHeading()
        isUpdating = false
    }

    deinit { stop() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if (manager.authorizationStatus == .authorizedWhenInUse ||
            manager.authorizationStatus == .authorizedAlways),
           !isUpdating {
            manager.headingFilter = isLocked ? Self.relaxedFilter : Self.preciseFilter
            manager.startUpdatingHeading()
            isUpdating = true
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        onHeading?(newHeading)
    }

    // Allow calibration during pre-match setup so the user can obtain a valid
    // heading. Suppress it once locked — calibration popups block UI mid-point
    // and the badge degrades gracefully to grey when accuracy is poor.
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return !isLocked
    }
}
