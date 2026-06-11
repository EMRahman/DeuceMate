// MatchSyncTransport.swift — shared WCSession transport used by both targets.
//
// Wraps the choice between sendMessage / transferUserInfo / transferFile so the
// per-platform delegates only have to express *intent* (send a record, send
// history, send a control message) rather than re-implement the size/reachability
// branching on each side.
//
// The transport talks to WCSession through the `MatchSyncSessing` seam below
// rather than to `WCSession` directly. That keeps the reachability- and
// size-gated routing logic in pure Foundation so it compiles — and is
// unit-testable with a fake session — on macOS, where WatchConnectivity is
// unavailable. The real `WCSession` conformance lives behind the
// `canImport(WatchConnectivity)` guard at the bottom of this file.
import Foundation
import os

/// Threshold at which we switch from `transferUserInfo` to `transferFile` for
/// large payloads. WCSession's documented limit is higher (~262KB) but the
/// transferUserInfo queue gets backed up by anything close to it; staying
/// well under keeps history sync responsive.
public let matchSyncUserInfoSizeLimit = 64_000

/// Minimal seam over the `WCSession` methods `MatchSyncTransport` relies on.
///
/// Abstracting these few calls (rather than depending on `WCSession` directly)
/// lets the transport's routing logic build and run on macOS package tests with
/// a fake session standing in for the unavailable WatchConnectivity stack.
public protocol MatchSyncSessing: AnyObject {
    /// True once the session has finished activating.
    var isActivated: Bool { get }
    /// True when the peer device is currently reachable for live `sendMessage`.
    var isReachable: Bool { get }
    /// Live message send. Mirrors `WCSession.sendMessage(_:replyHandler:errorHandler:)`.
    func sendMessage(_ message: [String: Any],
                     replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((Error) -> Void)?)
    /// Background-queued dictionary delivery (survives the peer being asleep).
    func queueUserInfo(_ userInfo: [String: Any])
    /// Background file transfer for payloads too large for `queueUserInfo`.
    func transferFile(at url: URL, metadata: [String: Any]?)
}

public final class MatchSyncTransport {
    private let session: MatchSyncSessing
    private let logger: Logger

    /// Designated initialiser. Takes any `MatchSyncSessing` so tests can inject a
    /// fake; production code uses the `WCSession` convenience initialiser below.
    public init(session: MatchSyncSessing,
                logger: Logger = Logger(subsystem: "com.deucemate.sync", category: "Transport")) {
        self.session = session
        self.logger = logger
    }

    // MARK: - State

    public var isActivated: Bool { session.isActivated }
    public var isReachable: Bool { session.isReachable }

    // MARK: - Sending records

    /// Sends a single `MatchRecord` checkpoint. When the peer is reachable we
    /// use `sendMessage` for fast delivery. When unreachable, in-progress
    /// checkpoints are silently dropped (a subsequent checkpoint will supersede
    /// them) but any standalone announcement is queued via `transferUserInfo`
    /// so it survives the peer's screen being locked.
    ///
    /// `completedClearsActive` controls whether the payload also tells the peer
    /// to clear its "active match" pointer (only true for finalised records).
    public func sendRecord(
        _ record: MatchRecord,
        completedClearsActive: Bool,
        announcement: String?
    ) {
        guard isActivated else { return }
        let data: Data
        do {
            data = try MatchSyncMessage.encode(record)
        } catch {
            logger.error("Failed to encode record \(record.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        if session.isReachable {
            let msg = MatchSyncPayloadBuilder.checkpointPayload(
                recordData: data,
                recordID: record.id,
                completedClearsActive: completedClearsActive,
                announcement: announcement
            )
            session.sendMessage(msg, replyHandler: nil) { [weak self] error in
                self?.logger.error("sendRecord failed: \(error.localizedDescription, privacy: .public)")
                if let ann = announcement { self?.queueAnnouncement(ann) }
            }
        } else if let ann = announcement {
            queueAnnouncement(ann)
        }
    }

    /// Sends a single `MatchRecord` reliably, falling back to `transferUserInfo`
    /// when the peer is unreachable. Used for one-shot pushes (manual entry
    /// recovery) where silent drop is unacceptable.
    public func sendRecordReliable(_ record: MatchRecord) {
        guard isActivated else { return }
        let data: Data
        do {
            data = try MatchSyncMessage.encode(record)
        } catch {
            logger.error("Failed to encode reliable record \(record.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        let payload = MatchSyncPayloadBuilder.singleRecordPayload(data: data)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                guard let self else { return }
                self.logger.error("sendRecordReliable sendMessage failed: \(error.localizedDescription, privacy: .public)")
                self.queueRecord(data: data, payload: payload)
            }
        } else {
            queueRecord(data: data, payload: payload)
        }
    }

    private func queueRecord(data: Data, payload: [String: Any]) {
        if data.count > matchSyncUserInfoSizeLimit {
            transferAsFile(data, key: MatchSyncKey.singleMatch)
        } else {
            session.queueUserInfo(payload)
        }
    }

    /// Sends the full match history. Switches to `transferFile` when the encoded
    /// payload would exceed the userInfo size limit (large back-catalogues).
    public func sendHistory(_ records: [MatchRecord]) {
        guard isActivated, !records.isEmpty else { return }
        let data: Data
        do {
            data = try MatchSyncMessage.encode(records)
        } catch {
            logger.error("Failed to encode history: \(error.localizedDescription, privacy: .public)")
            return
        }
        if data.count > matchSyncUserInfoSizeLimit {
            transferAsFile(data, key: MatchSyncKey.matchHistory)
        } else {
            session.queueUserInfo(MatchSyncPayloadBuilder.historyPayload(data: data))
        }
    }

    // MARK: - Control messages

    /// Sends a control payload (e.g. `clearActiveMatch`, `requestFullHistory`).
    /// `queueOnFailure` controls whether unreachable / errored sends fall back
    /// to `transferUserInfo`.
    public func sendControl(_ payload: [String: Any], queueOnFailure: Bool) {
        guard isActivated else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.logger.error("sendControl failed: \(error.localizedDescription, privacy: .public)")
                if queueOnFailure { self?.session.queueUserInfo(payload) }
            }
        } else if queueOnFailure {
            session.queueUserInfo(payload)
        }
    }

    /// Sends a TTS announcement. `completion(true)` means the peer was
    /// reachable and acknowledged; `completion(false)` means we fell back to
    /// `transferUserInfo` (announcement still queued, but no live reply).
    public func sendAnnouncement(_ text: String, completion: @escaping (Bool) -> Void) {
        guard isActivated else { completion(false); return }
        if session.isReachable {
            session.sendMessage(
                [MatchSyncKey.liveAnnouncement: text],
                replyHandler: { _ in completion(true) },
                errorHandler: { [weak self] error in
                    self?.logger.error("sendAnnouncement failed: \(error.localizedDescription, privacy: .public)")
                    self?.queueAnnouncement(text)
                    completion(false)
                }
            )
        } else {
            queueAnnouncement(text)
            completion(false)
        }
    }

    /// Pings the peer with a reply-handler. `completion(true, nil)` on reply,
    /// `completion(false, message)` otherwise.
    public func ping(completion: @escaping (Bool, String) -> Void) {
        guard isActivated else { completion(false, "Session not activated"); return }
        guard session.isReachable else {
            completion(false, "Peer not reachable")
            return
        }
        session.sendMessage(
            ["ping": true],
            replyHandler: { _ in completion(true, "Peer replied") },
            errorHandler: { error in completion(false, "Error: \(error.localizedDescription)") }
        )
    }

    // MARK: - Private

    private func queueAnnouncement(_ text: String) {
        session.queueUserInfo([MatchSyncKey.liveAnnouncement: text])
    }

    private func transferAsFile(_ data: Data, key: String) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(key)-\(UUID().uuidString).json")
        do {
            try data.write(to: tmpURL)
            session.transferFile(at: tmpURL, metadata: ["key": key])
            // WCSession copies the file internally; clean up our temp copy.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                try? FileManager.default.removeItem(at: tmpURL)
            }
        } catch {
            logger.error("transferAsFile failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }
}

// MARK: - WCSession conformance

#if canImport(WatchConnectivity)
import WatchConnectivity

/// Binds the real `WCSession` to the `MatchSyncSessing` seam. The `sendMessage`
/// and `isReachable` requirements are satisfied by WCSession's own members; the
/// rest forward to WCSession, discarding the transfer-handle return values the
/// transport does not use.
extension WCSession: MatchSyncSessing {
    public var isActivated: Bool { activationState == .activated }

    public func queueUserInfo(_ userInfo: [String: Any]) {
        _ = transferUserInfo(userInfo)
    }

    public func transferFile(at url: URL, metadata: [String: Any]?) {
        _ = transferFile(url, metadata: metadata)
    }
}

public extension MatchSyncTransport {
    /// Convenience initialiser binding the transport to the live `WCSession`.
    convenience init(session: WCSession = .default,
                     logger: Logger = Logger(subsystem: "com.deucemate.sync", category: "Transport")) {
        self.init(session: session as MatchSyncSessing, logger: logger)
    }
}
#endif
