import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

@main
struct DeuceMateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("selectedTheme") private var themeRawValue: String = AppTheme.default.rawValue
    @Environment(\.scenePhase) private var scenePhase
    private let store = PhoneStatsStore.shared
    private let syncService = PhoneMatchSyncService.shared
    private let announcementService = LiveAnnouncementService.shared

    init() {
        syncService.start(store: store)
        syncService.announcementService = announcementService
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(syncService)
                .environmentObject(announcementService)
                .environment(\.appTheme, AppTheme(rawValue: themeRawValue) ?? .default)
                .onChange(of: themeRawValue) { newValue in
                    syncService.sendTheme(newValue)
                }
                .onChange(of: scenePhase) { phase in
                    // Resume any initial restore, or push the local archive
                    // backup, whenever the app returns to the foreground.
                    if phase == .active {
                        store.syncICloudBackup()
                    }
                }
        }
    }
}
