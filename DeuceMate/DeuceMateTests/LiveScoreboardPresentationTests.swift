import DeuceMateCore
import SwiftUI
import XCTest
@testable import DeuceMate

final class LiveScoreboardPresentationTests: XCTestCase {
    @MainActor
    func testFirstScoreboardLayoutIsLandscapeAndDismissalRestoresPortrait() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let previousWindow = scene.keyWindow
        defer {
            window.isHidden = true
            previousWindow?.makeKey()
        }

        let service = PhoneMatchSyncService(isSessionSupported: { false }, activateSession: { _ in },
                                           scheduleAfter: { _, _ in },
                                           transport: MatchSyncTransport(session: FakePhoneSyncSession()))
        let record = MatchRecord(startTime: Date(), setScores: [SetScore(gamesMe: 2, gamesOpponent: 1)], stats: [])
        service.handle([.liveState(LiveMatchReply(state: LiveMatchState(record: record, inputEnabled: false),
                                                 sessionID: UUID(), sequence: 1))])

        let ready = expectation(description: "Portrait presenter appeared")
        let landscape = expectation(description: "Scoreboard laid out in landscape")
        let dismissed = expectation(description: "Scoreboard dismissed")
        var presentation: Binding<Bool>?
        var sizes: [CGSize] = []
        let host = UIHostingController(rootView: PresentationHost(onReady: { binding in
            guard presentation == nil else { return }
            presentation = binding
            ready.fulfill()
        }, onSize: { size in
            guard size.width > 0, size.height > 0 else { return }
            if size.width > size.height && !sizes.contains(where: { $0.width > $0.height }) {
                landscape.fulfill()
            }
            sizes.append(size)
        }, onDismiss: { dismissed.fulfill() })
            .environmentObject(service)
            .environmentObject(PhoneStatsStore.shared))
        window.rootViewController = host
        window.makeKeyAndVisible()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertLessThan(window.bounds.width, window.bounds.height)

        XCTAssertEqual(service.liveState?.record?.id, record.id)
        let isPresented = try XCTUnwrap(presentation)
        isPresented.wrappedValue = true
        await fulfillment(of: [landscape], timeout: 5)
        let first = try XCTUnwrap(sizes.first)
        XCTAssertGreaterThan(first.width, first.height, "Scoreboard layout sequence: \(sizes)")

        // A user can tap Close once the cover's opening transition completes.
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                host.presentedViewController != nil && host.transitionCoordinator == nil
                    && window.bounds.width > window.bounds.height
            }
        }, object: nil)
        await fulfillment(of: [visible], timeout: 5)
        isPresented.wrappedValue = false
        await fulfillment(of: [dismissed], timeout: 5)
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { window.bounds.width < window.bounds.height }
        }, object: nil)
        await fulfillment(of: [portrait], timeout: 5)
        XCTAssertEqual(AppDelegate.orientationLock, .portrait)
    }

    private struct PresentationHost: View {
        @State private var scoreboard = LiveScoreboardPresentation()
        var onReady: (Binding<Bool>) -> Void
        var onSize: (CGSize) -> Void
        var onDismiss: () -> Void

        var body: some View {
            Color.clear
                .onAppear { onReady($scoreboard.isPresented) }
                .fullScreenCover(isPresented: $scoreboard.isPresented, onDismiss: onDismiss) {
                    LiveScoreboardView { scoreboard.isPresented = false }
                        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onSize)
                }
        }
    }
}
