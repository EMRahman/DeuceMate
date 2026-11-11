//DeuceMateApp.swift
import SwiftUI
import WatchKit

@main
struct DeuceMateApp: App {
    @WKApplicationDelegateAdaptor(WorkoutRecoveryDelegate.self) private var recoveryDelegate
    @StateObject private var viewModel = ScoreViewModel()
    @State private var didStart = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--workout-ui-test") {
                WorkoutUITestRoot()
            } else if ProcessInfo.processInfo.arguments.contains("--walkthrough-ui-test") {
                WalkthroughUITestRoot()
            } else {
                productionRoot
            }
            #else
            productionRoot
            #endif
        }
    }

    private var productionRoot: some View {
        RootView()
            .environmentObject(viewModel)
            .environment(\.appTheme, viewModel.selectedTheme)
            .onAppear {
                guard !didStart else { return }
                didStart = true
                // Bind the view model to a local so every long-lived callback
                // below captures it weakly; implicitly capturing the
                // property strongly in this scope would defeat `[weak …]`.
                let model = viewModel
                model.loadState()
                model.workoutManager.requestAuthorization { [weak model] _ in
                    DispatchQueue.main.async {
                        guard let model else { return }
                        recoveryDelegate.recoverWorkout = { [weak model] in
                            model?.restoreWorkoutAfterLaunch()
                        }
                        model.restoreWorkoutAfterLaunch {
                            model.launchPresentationReady = true
                        }
                    }
                }
                // Start WatchConnectivity so completed/in-progress matches
                // are delivered to the paired iPhone companion app.
                let sync = WatchMatchSyncService.shared
                sync.onThemeReceived = { [weak model] rawValue in
                    model?.applyIncomingTheme(rawValue)
                }
                // Watch-only settings (bidirectional) pushed from phone
                sync.onStatsTrackingReceived = { [weak model] v in model?.applyIncomingStatsTracking(v) }
                sync.onChangeoverReceived = { [weak model] v in model?.applyIncomingChangeover(v) }
                // Shared settings pushed from phone
                sync.onAnnouncementsReceived = { [weak model] v in model?.applyIncomingAnnouncements(v) }
                sync.onIPhoneInputReceived = { [weak model] v in model?.applyIncomingIPhoneInput(v) }
                sync.onPlayerNameReceived = { [weak model] v in model?.applyIncomingPlayerName(v) }
                // Spectator score commands from the iPhone live scoreboard
                sync.onScoreCommandReceived = { [weak model] cmd, matchID in
                    model?.applyRemoteScoreCommand(cmd, matchID: matchID)
                }
                // Spectator categorization actions from the iPhone live scoreboard
                sync.onStatActionReceived = { [weak model] action, outcome, endingShot in
                    model?.applyRemoteStatAction(action, outcome: outcome, endingShot: endingShot)
                }
                sync.onCompletedMatchReceived = { [weak model] record in
                    model?.completeCurrentMatchIfMatching(record.id)
                }
                sync.onMatchTagsReceived = { [weak model] id, tags in
                    model?.applyIncomingMatchTags(tags, matchID: id)
                }
                model.syncService = sync
                // Register all inbound handlers before activation. An already
                // available phone payload can arrive immediately on start.
                sync.start()
            }
            .onChange(of: scenePhase) { _ in
                if scenePhase == .background {
                    viewModel.saveState()
                    viewModel.pauseHeadingMonitoring()
                } else if scenePhase == .active {
                    viewModel.startHeadingMonitoring()
                    // Health permission may have changed from the iPhone
                    // while we were away; the start-screen tracking strip
                    // must not keep claiming access we no longer have.
                    viewModel.workoutManager.refreshHealthAccess()
                }
            }
    }
}

final class WorkoutRecoveryDelegate: NSObject, WKApplicationDelegate {
    var recoverWorkout: (() -> Void)?

    func handleActiveWorkoutRecovery() {
        // If delivered before onAppear/authorization, normal launch restoration
        // still queries HealthKit. Later delivery shares the one-shot path.
        DispatchQueue.main.async { self.recoverWorkout?() }
    }
}

#if DEBUG
/// A deterministic presentation harness; no launch permissions or production session.
private struct WalkthroughUITestRoot: View {
    @State private var presented = true
    var body: some View {
        Button("Animated guide") { presented = true }
            .sheet(isPresented: $presented) {
                WalkthroughView(onDone: { presented = false }, onClose: { presented = false },
                                reduceMotionOverride: ProcessInfo.processInfo.arguments.contains("--walkthrough-reduce-motion") ? true : nil)
                    .environment(\.appTheme, .default)
            }
    }
}
#endif
