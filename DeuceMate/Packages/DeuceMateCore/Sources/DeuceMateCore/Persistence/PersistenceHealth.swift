// PersistenceHealth.swift — single source of truth for "a save or a read of the
// user's match data failed, and the user should be told".
//
// Both stores already log persistence failures to the unified log, which nobody
// running the app can see. For a scoring app a failed write means lost match
// data, so the failure has to reach the screen. This file owns the failure
// vocabulary and the user-facing copy; each app keeps a `PersistenceHealth`
// value (published from `ScoreViewModel` on the watch and `PhoneStatsStore` on
// the phone) and renders `warning` when it is non-nil.
//
// Pure value types so the precedence rules — which failure wins, what clears
// one — are unit-testable in the package with no simulator.
import Foundation

/// How loudly a failure should read in the UI.
public enum PersistenceSeverity: Int, Comparable, Sendable {
    /// Data already on disk is intact; something the user can see is degraded.
    case warning = 0
    /// Data the user just produced is not durable.
    case critical = 1

    public static func < (lhs: PersistenceSeverity, rhs: PersistenceSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The persistence operations whose failure is worth surfacing. One case per
/// distinct user-visible consequence — not per call site.
public enum PersistenceOperation: String, CaseIterable, Sendable {
    /// Writing the in-progress match checkpoint (watch `appState.json`).
    case saveLiveMatch
    /// Reading that checkpoint back at launch. Only reported when the file
    /// exists and could not be read — an absent file is a normal cold start.
    /// Critical, not a warning: the match the user was scoring is gone from the
    /// app's view, and unless the reader sets the file aside the next
    /// checkpoint write overwrites the only copy of it.
    case restoreLiveMatch
    /// Writing the finished-match archive.
    case saveMatchHistory
    /// Reading the archive. An unreadable archive is never treated as empty, so
    /// the consequence is an incomplete list rather than data loss.
    case readMatchHistory
    /// The archive decoded as garbage and was moved aside for recovery, so the
    /// store started from an empty list.
    case archiveQuarantined
    /// The archive existed but could not be read at launch, so the store runs
    /// in memory with all disk writes suspended for the rest of the process.
    case archiveWritesSuspended

    public var severity: PersistenceSeverity {
        switch self {
        case .saveLiveMatch, .restoreLiveMatch, .saveMatchHistory, .archiveWritesSuspended:
            return .critical
        case .readMatchHistory, .archiveQuarantined:
            return .warning
        }
    }
}

/// A single failed persistence operation, with the underlying error text kept
/// for the log line (never shown to the user — `PersistenceWarning` owns copy).
public struct PersistenceFailure: Equatable, Sendable {
    public let operation: PersistenceOperation
    public let detail: String
    public let date: Date

    public init(operation: PersistenceOperation, detail: String, date: Date = Date()) {
        self.operation = operation
        self.detail = detail
        self.date = date
    }
}

/// The result of one persistence operation, as reported by a store to whoever
/// owns the user-facing `PersistenceHealth`. Successes are reported too: they
/// are what clears a stale warning after a retry lands.
public enum PersistenceOutcome: Equatable, Sendable {
    case succeeded(PersistenceOperation)
    case failed(PersistenceFailure)
}

/// Implemented by stores that report their write/read outcomes upward instead
/// of only logging them. The owner (a view model or an `ObservableObject`
/// store) installs the closure and folds each outcome into a
/// `PersistenceHealth`. Callbacks are delivered on the main queue so the
/// receiver can publish straight from them.
public protocol PersistenceOutcomeReporting: AnyObject {
    var onPersistenceOutcome: ((PersistenceOutcome) -> Void)? { get set }
}

/// What the user reads. Resolved from the failed operation so the two apps can
/// never drift in how they describe the same failure.
public struct PersistenceWarning: Equatable, Sendable {
    public let title: String
    public let message: String
    public let systemImage: String
    public let severity: PersistenceSeverity
}

/// The most recent persistence failure that still matters, plus the rules for
/// replacing and clearing it.
///
/// Precedence is deliberate: a critical failure (something the user produced is
/// not on disk) is never displaced by a subsequent warning-level one. Among
/// equally severe failures the newest wins, because it describes the current
/// state of the store.
public struct PersistenceHealth: Equatable, Sendable {
    /// The failure currently worth showing, if any.
    public private(set) var failure: PersistenceFailure?

    public init(failure: PersistenceFailure? = nil) {
        self.failure = failure
    }

    /// Record a failure. Returns `true` only when what the user would *read*
    /// changed, so an observer can skip republishing. A repeat of the same
    /// operation resolves to an identical `PersistenceWarning`, and the live
    /// checkpoint write runs on every point — republishing there would fire
    /// `objectWillChange` per point and redraw the scoreboard for a message
    /// already on screen.
    @discardableResult
    public mutating func record(_ incoming: PersistenceFailure) -> Bool {
        if let current = failure {
            if current.operation.severity > incoming.operation.severity { return false }
            if current.operation == incoming.operation {
                // Keep the newer failure — its `date`/`detail` describe the
                // current state of the store — but report no visible change.
                failure = incoming
                return false
            }
        }
        failure = incoming
        return true
    }

    /// Clear the displayed failure when the *same* operation later succeeds.
    /// Scoped to the same operation on purpose: a successful history write says
    /// nothing about whether the live-match checkpoint is being saved.
    /// Returns `true` when something was cleared.
    @discardableResult
    public mutating func recordSuccess(of operation: PersistenceOperation) -> Bool {
        guard failure?.operation == operation else { return false }
        failure = nil
        return true
    }

    /// Dismiss the warning at the user's request, without a successful retry.
    public mutating func acknowledge() {
        failure = nil
    }

    /// Fold a store-reported outcome in. Returns `true` when the displayed
    /// failure changed, so an observer can avoid a redundant publish.
    @discardableResult
    public mutating func apply(_ outcome: PersistenceOutcome) -> Bool {
        switch outcome {
        case .succeeded(let operation): return recordSuccess(of: operation)
        case .failed(let failure):      return record(failure)
        }
    }

    /// Copy for the failure currently held, or `nil` when the store is healthy.
    public var warning: PersistenceWarning? {
        failure.map { Self.warning(for: $0.operation) }
    }

    public static func warning(for operation: PersistenceOperation) -> PersistenceWarning {
        switch operation {
        case .saveLiveMatch:
            return PersistenceWarning(
                title: "Match not saved",
                message: "This match couldn't be saved to storage. Points scored since the last successful save may be lost if the app closes.",
                systemImage: "exclamationmark.triangle.fill",
                severity: operation.severity
            )
        case .restoreLiveMatch:
            return PersistenceWarning(
                title: "Couldn't restore match",
                message: "A saved match was found but couldn't be read, so scoring started fresh. The unreadable file was kept for recovery instead of being overwritten.",
                systemImage: "exclamationmark.arrow.circlepath",
                severity: operation.severity
            )
        case .saveMatchHistory:
            return PersistenceWarning(
                title: "History not saved",
                message: "Finished matches couldn't be written to storage. Recent matches may be missing after a restart.",
                systemImage: "exclamationmark.triangle.fill",
                severity: operation.severity
            )
        case .readMatchHistory:
            return PersistenceWarning(
                title: "History unreadable",
                message: "Saved matches couldn't be read, so the list may be incomplete. Nothing has been deleted.",
                systemImage: "questionmark.folder",
                severity: operation.severity
            )
        case .archiveQuarantined:
            return PersistenceWarning(
                title: "Archive couldn't be read",
                message: "The stored archive was damaged and has been set aside for recovery, so matches may be missing from the list.",
                systemImage: "questionmark.folder",
                severity: operation.severity
            )
        case .archiveWritesSuspended:
            return PersistenceWarning(
                title: "Saving is paused",
                message: "The archive couldn't be read at launch, so nothing new is being written to disk — this protects the stored matches. Restart the app to try again.",
                systemImage: "exclamationmark.triangle.fill",
                severity: operation.severity
            )
        }
    }
}
