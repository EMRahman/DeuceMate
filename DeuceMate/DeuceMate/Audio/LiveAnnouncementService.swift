// LiveAnnouncementService.swift — iPhone TTS announcements during a live match.
//
// Announcements are FOREGROUND-ONLY. The app declares no audio background mode
// and never keeps an audio session alive in the background: a score is spoken
// only while DeuceMate is on screen. If the app is backgrounded or the phone is
// locked, the announcement is skipped (the score is still visible on the live
// scoreboard and on the watch). This keeps the app clear of the background-audio
// "keep-alive" pattern that App Review guideline 2.5.4 prohibits.
import AVFoundation
import Combine
import UIKit
import os

@MainActor
final class LiveAnnouncementService: ObservableObject {
    static let shared = LiveAnnouncementService()

    @Published private(set) var isEnabled: Bool =
        UserDefaults.standard.bool(forKey: "liveAnnouncementsEnabled")

    private let synthesizer = AVSpeechSynthesizer()

    private let logger = Logger(subsystem: "com.deucemate.audio", category: "Announcements")

    // AVSpeechSynthesizerDelegate requires NSObject; use a private proxy so
    // LiveAnnouncementService itself doesn't inherit NSObject (which would
    // prevent ObservableObject synthesis).
    private lazy var synthDelegate = SynthDelegate(owner: self)

    private init() {
        synthesizer.delegate = synthDelegate
    }

    // MARK: - Public API

    /// User preference for spoken announcements. Turning it off stops any
    /// in-flight speech immediately.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "liveAnnouncementsEnabled")
        if !enabled { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// Called by the sync service when the watch starts (`true`) or ends
    /// (`false`) a live match. Announcements are foreground-only, so there is no
    /// background keep-alive to bring up or down — we only stop any in-flight
    /// speech when the match ends. Retained for sync call-site compatibility.
    func setMatchLive(_ live: Bool) {
        if !live { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// Speaks a live score announcement — only while the app is in the
    /// foreground. If the app is backgrounded or suspended (e.g. the phone is
    /// locked), the announcement is dropped rather than queued: a stale score
    /// spoken minutes later would be wrong, and the score is still on screen on
    /// the live scoreboard and on the watch.
    func speak(_ text: String) {
        guard isEnabled else { return }
        guard UIApplication.shared.applicationState != .background else { return }
        speakNow(text)
    }

    /// Speaks a one-off phrase (the Settings voice test). Always foreground.
    func previewVoice(_ text: String) {
        speakNow(text)
    }

    // MARK: - Speech

    private func speakNow(_ text: String) {
        // Cancel any in-flight utterance before starting the new one. This fires
        // didCancel, but the new utterance below is already queued by the time it
        // runs, so releaseSessionIfIdle()'s `!isSpeaking` guard keeps the session
        // up for immediate reuse instead of tearing it down between points.
        synthesizer.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        do {
            // Duck other audio while the score is spoken; mix so we don't stop it.
            try session.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            logger.error("audio session error: \(error.localizedDescription, privacy: .public)")
        }
        enqueueUtterance(text)
    }

    private func enqueueUtterance(_ text: String) {
        let utt = AVSpeechUtterance(string: text)
        // Announcement strings are always English tennis terminology ("Deuce",
        // "Advantage …"), so the voice is pinned to English regardless of
        // device locale — a localized voice would mispronounce these terms.
        utt.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utt.rate = 0.50
        utt.preUtteranceDelay = 0.1
        synthesizer.speak(utt)
    }

    // Called by SynthDelegate when an utterance finishes OR is cancelled.
    fileprivate func releaseSessionIfIdle() {
        // Only release the session once nothing else is queued, so back-to-back
        // announcements don't deactivate a session that's about to be reused —
        // and so other audio (music, podcasts) un-ducks promptly between points.
        // Runs for both natural completion (didFinish) and cancellation
        // (didCancel — e.g. announcements switched off or the match ended
        // mid-utterance), so a cancelled announcement can't strand the session
        // active and ducking other audio.
        guard !synthesizer.isSpeaking else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        } catch {
            // A stranded active session keeps other audio ducked, so the user
            // may hear the symptom; nothing in-app can fix it, but it must not
            // be invisible when diagnosing "music stays quiet after a point".
            logger.error("Failed to deactivate audio session: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Delegate proxy

private final class SynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var owner: LiveAnnouncementService?
    init(owner: LiveAnnouncementService) { self.owner = owner }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                            didFinish utterance: AVSpeechUtterance) {
        guard let owner else { return }
        Task { @MainActor in owner.releaseSessionIfIdle() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        guard let owner else { return }
        Task { @MainActor in owner.releaseSessionIfIdle() }
    }
}
