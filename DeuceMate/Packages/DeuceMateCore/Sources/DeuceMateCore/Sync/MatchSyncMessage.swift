// MatchSyncMessage.swift — WatchConnectivity wire-format constants and helpers.
import Foundation

/// Keys used in WCSession userInfo and sendMessage dictionaries.
public enum MatchSyncKey {
    /// Single `MatchRecord` encoded as JSON `Data`.
    public static let singleMatch = "match"
    /// Array of `MatchRecord` encoded as JSON `Data` (full-history sync).
    public static let matchHistory = "matchHistory"
    /// Sent by the phone to request the watch's full history.
    public static let requestFullHistory = "requestFullHistory"
    /// Optional plain-text score announcement for the iPhone to speak aloud.
    public static let liveAnnouncement = "ann"
    /// UUID string of the match currently active on the watch, sent with every checkpoint.
    public static let activeMatchID = "activeMatchID"
    /// Sent by the watch when a match ends (completed or abandoned) to clear the active match on the phone.
    public static let clearActiveMatch = "clearActiveMatch"
    /// Watch → phone manifest of the match-id UUID strings the watch currently
    /// holds, JSON-encoded as `[String]`. The watch caps its history at 10, so
    /// this is small. The phone uses it to badge each match as stored on both
    /// devices, the phone only, or the watch only. Sent alongside every full
    /// history push and record checkpoint, and after a watch-side delete.
    public static let watchManifest = "watchManifest"
    /// Phone → watch command to delete a single match from the watch only (the
    /// phone keeps its own archive copy). Carries `deleteMatchID`. Mirrors the
    /// `scoreCommand` / `scoreCommandMatchID` pattern. There is no resync key —
    /// pulling a watch-only match down reuses `requestFullHistory`, since the
    /// watch holds ≤10 matches and already replies with its full history.
    public static let deleteMatchOnWatch = "deleteMatchOnWatch"
    /// UUID string of the match a `deleteMatchOnWatch` command targets.
    public static let deleteMatchID = "deleteMatchID"
    /// Phone → watch resolved player max heart rate in bpm (Int).
    public static let pulseCoachMaxHR = "pulseCoachMaxHR"
    /// Player birth year used to derive max HR via `220 − age`; synced bidirectionally. 0 means unset.
    public static let userBirthYear = "userBirthYear"
    /// True when the birth year originated from the user's Health record (read on the watch via HealthKit).
    /// Synced bidirectionally so the iPhone UI can label the value as "from Health". Cleared whenever the
    /// user manually picks a different year on either device.
    public static let userBirthYearFromHealth = "userBirthYearFromHealth"
    /// Manual max-HR override in bpm; synced bidirectionally. 0 means auto.
    public static let userMaxHROverride = "userMaxHROverride"
    /// Raw value of the selected `AppTheme`, synced bidirectionally so the skin matches on both devices.
    public static let selectedTheme = "selectedTheme"

    // MARK: - Watch-only settings (phone → watch)
    /// Phone → watch point-outcome tracking switch (Bool).
    public static let statsTrackingEnabled = "statsTrackingEnabled"
    /// Phone → watch HealthKit workout session switch (Bool).
    public static let workoutSessionEnabled = "workoutSessionEnabled"
    /// Phone → watch changeover compass switch (Bool).
    public static let checkChangeover = "checkChangeover"

    // MARK: - Shared settings (bidirectional, last-write wins)
    /// Whether scores should be announced aloud through the iPhone speaker; synced bidirectionally.
    public static let announcementsEnabled = "announcementsEnabled"
    /// "iPhone Input" — when enabled, a spectator can swipe on the iPhone live scoreboard
    /// to win/lose/undo points. Bidirectional, last-write wins.
    public static let iPhoneInputEnabled = "iPhoneInputEnabled"
    /// Player's preferred display name used in spoken announcements. Bidirectional,
    /// last-write wins. Empty string means "unset" (fall back to "you").
    public static let playerName = "playerName"

    // MARK: - Score commands (iPhone → watch, gated by iPhoneInputEnabled)
    /// Scoring action issued by the iPhone spectator. Values are
    /// `scoreCommandWinMe`, `scoreCommandWinOpp`, or `scoreCommandUndo`.
    public static let scoreCommand = "scoreCommand"
    /// UUID string of the match the iPhone *displayed* when the swipe happened.
    /// The watch rejects commands whose match id doesn't equal its current live
    /// match identity, so a stale `activeMatchID` on the phone (e.g. missed
    /// `clearActiveMatch`) can never score points in an unrelated later match.
    public static let scoreCommandMatchID = "scoreCommandMatchID"
    public static let scoreCommandWinMe = "winMe"
    public static let scoreCommandWinOpp = "winOpp"
    public static let scoreCommandUndo = "undo"

    // MARK: - Pending point categorization mirror (watch → iPhone)
    /// JSON-encoded `PendingPointInfo` describing the point waiting to be
    /// categorized on the watch. Mirrored to the iPhone so a spectator can
    /// complete the post-point stat from either device.
    public static let pendingPoint = "pendingPoint"
    /// Raw value of `PointOutcome` when the watch has advanced to phase 2 of
    /// the categorization sheet (outcome chosen, ending-shot still pending).
    /// Absent when on phase 1.
    public static let pendingPointOutcome = "pendingPointOutcome"
    /// Sent by the watch when the pending categorization is committed,
    /// cancelled, or undone — instructs the iPhone to dismiss its sheet.
    public static let clearPendingPoint = "clearPendingPoint"

    // MARK: - Stat action commands (iPhone → watch, gated by iPhoneInputEnabled)
    /// Categorization action issued by the iPhone. One of `statActionSelectOutcome`,
    /// `statActionCommitEndingShot`, or `statActionCancelOutcomeSelection`.
    public static let statAction = "statAction"
    /// Raw value of `PointOutcome` accompanying a `statActionSelectOutcome`.
    public static let statActionOutcome = "statActionOutcome"
    /// Raw value of `EndingShot` accompanying a `statActionCommitEndingShot`.
    public static let statActionEndingShot = "statActionEndingShot"
    public static let statActionSelectOutcome = "selectOutcome"
    public static let statActionCommitEndingShot = "commitEndingShot"
    public static let statActionCancelOutcomeSelection = "cancelOutcomeSelection"
    /// Rolls the whole point back from the categorization sheet. Routed through
    /// the stat-action path rather than `scoreCommand` because the watch's
    /// `applyRemoteScoreCommand` rejects every score command while a stat is
    /// pending — the exact state in which the iPhone panel is visible.
    public static let statActionUndoPoint = "undoPoint"
}

/// Protocol implemented by the sync service on each platform.
public protocol MatchSyncService: AnyObject {
    /// Start the WCSession on this platform.
    func start()
    /// Send one record from the watch to the phone (queued, survives suspension).
    /// `announcement` is an optional TTS string the phone should speak aloud.
    func sendMatch(_ record: MatchRecord, announcement: String?)
    /// Send the full history from the watch to the phone.
    func sendFullHistory(_ records: [MatchRecord])
    /// Notify the phone that no match is currently active (match ended or abandoned).
    func clearActiveMatch()
    /// Watch → phone mirror of the in-progress categorization state. Phone
    /// renders an identical sheet so the spectator can complete the stat from
    /// either device. `pending == nil` means "no pending categorization —
    /// dismiss any sheet still up." Outcome is only non-nil when the watch has
    /// advanced to phase 2 of the sheet.
    func sendPendingPointState(_ pending: PendingPointInfo?, outcome: PointOutcome?)
    /// ISO 8601 date of the last successfully processed sync, if any.
    var lastSyncDate: Date? { get }
}

public extension MatchSyncService {
    /// Default no-op so platforms that don't yet emit pending-state updates
    /// (e.g. the phone) compile without boilerplate.
    func sendPendingPointState(_ pending: PendingPointInfo?, outcome: PointOutcome?) {}
}

// MARK: - Encoding helpers

public extension MatchSyncMessage {
    static func encode(_ record: MatchRecord) throws -> Data {
        try JSONEncoder().encode(record)
    }

    static func decode(_ data: Data) throws -> MatchRecord {
        try JSONDecoder().decode(MatchRecord.self, from: data)
    }

    static func encode(_ records: [MatchRecord]) throws -> Data {
        try JSONEncoder().encode(records)
    }

    static func decodeArray(_ data: Data) throws -> [MatchRecord] {
        try JSONDecoder().decode([MatchRecord].self, from: data)
    }
}

/// Namespace for the encoding helpers above.
public enum MatchSyncMessage {}
