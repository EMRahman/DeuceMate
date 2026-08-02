//DeuceMateApp.swift
import SwiftUI
import WatchKit

@main
struct DeuceMateApp: App {
    @StateObject private var viewModel = ScoreViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
                .environment(\.appTheme, viewModel.selectedTheme)
                .onAppear {
                    viewModel.loadState()
                    viewModel.workoutManager.requestAuthorization { _ in
                        viewModel.resumeWorkoutIfMatchInProgress()
                    }
                    // Start WatchConnectivity so completed/in-progress matches
                    // are delivered to the paired iPhone companion app.
                    let sync = WatchMatchSyncService.shared
                    sync.start()
                    sync.onThemeReceived = { [weak viewModel] rawValue in
                        viewModel?.applyIncomingTheme(rawValue)
                    }
                    // Watch-only settings (bidirectional) pushed from phone
                    sync.onStatsTrackingReceived = { [weak viewModel] v in viewModel?.applyIncomingStatsTracking(v) }
                    sync.onChangeoverReceived = { [weak viewModel] v in viewModel?.applyIncomingChangeover(v) }
                    // Shared settings pushed from phone
                    sync.onAnnouncementsReceived = { [weak viewModel] v in viewModel?.applyIncomingAnnouncements(v) }
                    sync.onIPhoneInputReceived = { [weak viewModel] v in viewModel?.applyIncomingIPhoneInput(v) }
                    sync.onPlayerNameReceived = { [weak viewModel] v in viewModel?.applyIncomingPlayerName(v) }
                    // Spectator score commands from the iPhone live scoreboard
                    sync.onScoreCommandReceived = { [weak viewModel] cmd, matchID in
                        viewModel?.applyRemoteScoreCommand(cmd, matchID: matchID)
                    }
                    // Spectator categorization actions from the iPhone live scoreboard
                    sync.onStatActionReceived = { [weak viewModel] action, outcome, endingShot in
                        viewModel?.applyRemoteStatAction(action, outcome: outcome, endingShot: endingShot)
                    }
                    viewModel.syncService = sync
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
}
