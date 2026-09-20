import SwiftUI
import Foundation
import DeuceMateCore

/// The offer and guide share one presentation so launch sheets never compete.
struct WalkthroughEntryView: View {
    let offer: Bool
    let coordinator: WalkthroughCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var started = false

    var body: some View {
        if !offer || started {
            WalkthroughView(onDone: { coordinator.complete(); dismiss() }, onClose: { dismiss() })
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Learn the controls").font(.headline)
                    Text("Tap to start each example, then watch its gesture and result. No match or workout is saved.")
                        .font(.footnote)
                    Button("Show guide") { coordinator.markSeen(); started = true }
                    Button("Not now") { coordinator.markSeen(); dismiss() }
                }.padding()
            }
        }
    }
}

struct WalkthroughView: View {
    let onDone: () -> Void
    let onClose: () -> Void
    var reduceMotionOverride: Bool? = nil
    @StateObject private var model = WalkthroughViewModel()
    @State private var selectedPreview = false
    @State private var demoElapsedSeconds = 0
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @Environment(\.scenePhase) private var scenePhase
    private var session: WalkthroughSession { model.session }
    private var metrics: (heartRate: Int, kilocalories: Int, elapsedSeconds: Int) {
        WalkthroughFixtures.demoMetrics(for: session.step)
    }
    private var showsIntroduction: Bool {
        session.phase == .situation && scenePhase == .active
    }
    var body: some View {
        ZStack {
            if session.phase == .done {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36)).foregroundStyle(.green)
                    Text("Ready to play").font(.headline)
                }
            } else {
                matchReplica
                if session.phase == .outcome || session.phase == .endingShot ||
                    session.phase == .stats || session.phase == .changeover {
                    demonstration
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay {
            if showsIntroduction {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if showsIntroduction {
                Button(action: beginExample) {
                    ZStack {
                        Color.clear.contentShape(Rectangle())
                        guideCommentary.padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(session.step.introduction) Play example.")
                .accessibilityIdentifier("guidePlayExample")
                .accessibilityAction(named: Text("Continue")) { beginExample() }
            }
        }
        .overlay(alignment: .top) { guideHeader }
        .onAppear { demoElapsedSeconds = metrics.elapsedSeconds }
        .onChange(of: session.generation) { _ in
            demoElapsedSeconds = metrics.elapsedSeconds
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active && session.phase != .situation {
                model.restartCurrentExample()
            }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                demoElapsedSeconds += 1
            }
        }
        .task(id: ResultRun(generation: session.generation, phase: session.phase,
                            active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            let generation = session.generation
            let phase = session.phase
            let animationDelay: UInt64
            switch phase {
            case .result: animationDelay = reduceMotion ? 0 : 250_000_000
            case .stats: animationDelay = reduceMotion ? 550_000_000 : 1_300_000_000
            case .done: animationDelay = 0
            default: return
            }
            // Keep the full-color result visible for one second after its animation.
            let baseHold: UInt64 = voiceOverEnabled ? (phase == .done ? 3_000_000_000 : 8_000_000_000) : 1_000_000_000
            // Leave the game-winning score on screen one second longer.
            let hold = baseHold + (phase == .result && session.step == .winGame ? 1_000_000_000 : 0)
            do { try await Task.sleep(nanoseconds: animationDelay + hold) } catch { return }
            guard !Task.isCancelled, generation == session.generation,
                  session.phase == phase, scenePhase == .active else { return }
            if phase == .done {
                onDone()
            } else {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    model.advanceAfterResult()
                }
            }
        }
        .task(id: AnimationRun(generation: session.generation, active: scenePhase == .active,
                               playing: session.phase != .situation)) {
            guard scenePhase == .active && session.phase != .situation else { return }
            let generation = session.generation
            while !model.isDisposed && !session.demonstrationFinished {
                let delay = beatDuration
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                catch { return }
                guard !Task.isCancelled, generation == session.generation else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    model.advanceDemonstration(generation: generation)
                }
                announceResult()
            }
        }
        .onDisappear { model.dispose() }
    }

    /// Uses the live match layout and sizing; guide controls are independent overlays.
    private var matchReplica: some View {
        VStack(spacing: 0) {
            scoreboard
            Group {
                if let reminder = session.reminder {
                    EndsSwitchReminderBanner(shouldSwitch: reminder)
                } else {
                    MomentumBadgeView(recentPoints: session.recentWinners)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Recent demo points: \(session.recentWinners.map { $0 == .me ? "Me" : "Opponent" }.joined(separator: ", "))")
                        .accessibilityIdentifier("guideMomentum")
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    CourtSideView(isDeuceSide: session.isDeuceSide, server: session.state.currentServer)
                    HeartRateBadgeContent(heartRate: Double(metrics.heartRate))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Demo heart rate: \(metrics.heartRate) beats per minute")
                        .accessibilityIdentifier("guideHeartRate")
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 4) {
                Text("🔥 \(metrics.kilocalories) kcal")
                Text("·")
                Text("🕐 \(durationText)")
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Demo calories: \(metrics.kilocalories) kilocalories. Elapsed time: \(durationText)")
            .accessibilityIdentifier("guideMetrics")
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var guideHeader: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 24, alignment: .leading)
            }
                .contentShape(Rectangle())
                .accessibilityLabel("Close guide")
                .accessibilityIdentifier("guideClose")
            Spacer()
            Text("DEMO").foregroundStyle(.yellow).allowsHitTesting(false)
            Spacer()
            Text("\(session.step.rawValue)/\(WalkthroughStep.allCases.count)")
                .accessibilityIdentifier("guideProgress")
                .allowsHitTesting(false)
        }
        .font(.system(size: 10, weight: .bold))
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var guideCommentary: some View {
        commentaryContent
    }

    private var commentaryContent: some View {
        VStack(spacing: 3) {
            Text(introductionText)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(4).minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
            Label("Tap to play", systemImage: "play.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.yellow)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.colors.surface.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.yellow.opacity(0.6))))
    }
    private func beginExample() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            model.beginExample()
        }
    }
    private func announceResult() {
        if #available(watchOS 10.0, *),
           session.phase == .result || session.phase == .stats ||
           session.phase == .changeover || session.phase == .postChangeoverScore {
            AccessibilityNotification.Announcement(session.feedback).post()
        }
    }
    private var durationText: String {
        let minutes = demoElapsedSeconds / 60
        let seconds = demoElapsedSeconds % 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 { return "\(hours) h \(remainingMinutes) m \(seconds) s" }
        return "\(minutes) m \(seconds) s"
    }
    private var introductionText: String {
        switch session.step {
        case .winPoint: return "Swipe up when you win a point"
        case .losePoint: return "Swipe down when you lose a point"
        case .undoPoint: return "Swipe left to undo the last point"
        case .unforcedError: return "If point tracking enabled; record your loss for an unforced error during a rally."
        case .secondServe: return "If point tracking enabled; double tap to record a second serve"
        case .doubleFault: return "If point tracking enabled; double fault can be logged."
        case .findStat: return "If point tracking enabled; swipe right to open Live Stats"
        case .winGame: return "40–0 at 1–0. One point wins the game"
        case .oddSet: return "40–0 at 5–3. One point wins the set. Notice the sticky reminder until the next point"
        }
    }
    private struct AnimationRun: Equatable {
        let generation: UUID
        let active: Bool
        let playing: Bool
    }
    private struct ResultRun: Equatable {
        let generation: UUID
        let phase: WalkthroughSession.Phase
        let active: Bool
    }
    private var beatDuration: Double {
        switch session.phase {
        case .secondServeTap, .gesture, .nextSetGesture: return reduceMotion ? 1.8 : 1.2
        case .outcome, .endingShot: return 2.0
        case .changeover: return 3.0
        case .reminder: return 1.0
        case .postChangeoverScore: return voiceOverEnabled ? 5.0 : 1.0
        default: return 1.0
        }
    }
    @ViewBuilder private var demonstration: some View {
        switch session.phase {
        case .outcome, .endingShot:
            categoryPreview.padding(.horizontal, 8)
        case .stats:
            statsPreview.padding(.horizontal, 8)
        case .changeover:
            ZStack {
                Color.black.opacity(0.80).ignoresSafeArea()
                VStack(spacing: 6) {
                if let changeover = session.changeover {
                    Text(changeover.symbol)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(changeover.reason.displayText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                selectionPreview("OK", chosen: selectedPreview)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18))))
                .padding(.horizontal, 12)
            }
            .accessibilityIdentifier("guideChangeover")
            .allowsHitTesting(false)
            .task(id: session.phase) { await animateSelection() }
        default:
            EmptyView()
        }
    }
    private var scoreboard: some View {
        VStack(spacing: 2) {
            scoreRow(.me)
            scoreRow(.opponent)
        }
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.colors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12))))
        .padding(.horizontal, 8)
        .overlay {
            if session.phase == .secondServeTap {
                GuideDoubleTapOverlay(reduceMotion: reduceMotion)
                    .id(session.phase)
            } else if session.phase == .gesture || session.phase == .nextSetGesture {
                GuideGestureOverlay(action: session.gesture, reduceMotion: reduceMotion)
                    .id(session.phase)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.scoreDescription)
        .accessibilityIdentifier("guideScoreboard")
    }
    private func scoreRow(_ player: Player) -> some View {
        let isMe = player == .me
        let color = isMe ? theme.colors.me : theme.colors.opponent
        return ScoringScoreRow(isMe: isMe, label: isMe ? "Me" : "Op",
            background: (isMe ? theme.colors.meRow : theme.colors.opponentRow).opacity(0.55), preview: false) {
                Group {
                    if session.state.currentServer == player {
                        Text("🎾").font(.system(size: 16))
                            .frame(width: 32, height: 22)
                            .overlay(alignment: .topTrailing) {
                                if session.isOnSecondServe {
                                    Text("2").font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.black)
                                        .frame(width: 10, height: 10)
                                        .background(Circle().fill(Color.yellow))
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                    else { Circle().fill(Color.white.opacity(0.12)).frame(width: 18, height: 18).opacity(0.35) }
                }
            } cells: {
                ForEach(Array(session.state.sets.enumerated()), id: \.offset) { index, set in
                    Text("\(isMe ? set.gamesMe : set.gamesOpponent)")
                        .frame(width: 24).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(index == session.state.sets.count - 1 ? color.opacity(isMe ? 0.8 : 0.85) : Color.white.opacity(0.14)))
                }
            } badge: {
                ScoringPointBadge(label: session.pointLabel(isMe ? session.state.currentPointsMe : session.state.currentPointsOpponent),
                    background: color, flashColor: color, flashOpacity: 0)
            }
    }
    private var categoryPreview: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(session.phase == .outcome ? "Lost — Your serve" : "Shot of the error?")
                    .font(.caption2.weight(.semibold))
                if session.step == .doubleFault && session.phase == .outcome {
                    Text("2nd")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.yellow.opacity(0.85)))
                        .foregroundStyle(.black)
                }
            }
            if session.phase == .outcome {
                if session.step == .doubleFault {
                    HStack(spacing: 4) {
                        categoryTile("Double Fault", chosen: selectedPreview)
                        categoryTile("Unforced Error", chosen: false)
                    }
                    HStack(spacing: 4) {
                        categoryTile("Forced Error", chosen: false)
                        categoryTile("Winner", chosen: false)
                    }
                } else {
                    HStack(spacing: 4) {
                        categoryTile("Unforced Error", chosen: selectedPreview)
                        categoryTile("Forced Error", chosen: false)
                    }
                    categoryTile("Winner", chosen: false)
                }
            } else {
                HStack(spacing: 4) {
                    categoryTile("S+1", chosen: false)
                    categoryTile("Rally", chosen: selectedPreview)
                }
            }
        }
        .padding(6).background(RoundedRectangle(cornerRadius: 12).fill(theme.colors.surface))
        .accessibilityIdentifier("guideCategoryPreview")
        .task(id: session.phase) { await animateSelection() }
    }
    private func categoryTile(_ label: String, chosen: Bool) -> some View {
        Text(label).font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(chosen ? Color.green.opacity(0.6) : Color.gray.opacity(0.2)))
            .overlay(alignment: .bottomTrailing) {
                if chosen { selectionMarker }
            }
    }
    private func selectionPreview(_ label: String, chosen: Bool) -> some View {
        Text(label).font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Capsule().fill(chosen ? Color.green.opacity(0.6) : Color.gray.opacity(0.2)))
            .overlay(alignment: .trailing) {
                if chosen { selectionMarker.padding(.trailing, 12) }
            }
    }
    private func animateSelection() async {
        selectedPreview = false
        do { try await Task.sleep(nanoseconds: 650_000_000) } catch { return }
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selectedPreview = true }
    }
    private var selectionMarker: some View {
        Image(systemName: reduceMotion ? "checkmark.circle.fill" : "hand.tap.fill")
            .font(.system(size: 18)).foregroundStyle(.white)
            .scaleEffect(reduceMotion ? 1 : 1.12)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatCount(2, autoreverses: true), value: session.phase)
            .accessibilityHidden(true)
    }
    private var statsPreview: some View {
        VStack(spacing: 4) {
            Text("Live Stats").font(.caption2.weight(.bold))
            ScrollViewReader { reader in
                ScrollView {
                    MatchStatsContent(stats: session.points, matchType: .singles)
                }.frame(height: 95).scrollDisabled(true)
                .task {
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) {
                        reader.scrollTo("countStat-Unforced Errors", anchor: .top)
                    }
                }
            }
        }.padding(6).background(RoundedRectangle(cornerRadius: 12).fill(theme.colors.surface))
        .accessibilityIdentifier("guideStatsPreview")
    }
}

/// Demonstrates the live scoreboard's double tap without scoring a point.
private struct GuideDoubleTapOverlay: View {
    let reduceMotion: Bool
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 25))
                .scaleEffect(pulsing ? 0.82 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2).repeatCount(2, autoreverses: true), value: pulsing)
            Text("×2").font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white)
        .shadow(color: .black, radius: 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { pulsing = true }
    }
}

/// A visible trail and moving touch marker demonstrate the swipe on the score itself.
private struct GuideGestureOverlay: View {
    let action: ScoreInputAction
    let reduceMotion: Bool
    @State private var moved = false
    private var vector: CGSize {
        switch action {
        case .win: return CGSize(width: 0, height: -34)
        case .lose: return CGSize(width: 0, height: 34)
        case .undo: return CGSize(width: -54, height: 0)
        case .stats: return CGSize(width: 54, height: 0)
        }
    }
    private var arrow: String {
        switch action {
        case .win: return "arrow.up"
        case .lose: return "arrow.down"
        case .undo: return "arrow.left"
        case .stats: return "arrow.right"
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            Path { path in
                path.move(to: CGPoint(x: center.x - vector.width / 2, y: center.y - vector.height / 2))
                path.addLine(to: CGPoint(x: center.x + vector.width / 2, y: center.y + vector.height / 2))
            }.stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [3, 5]))
            Image(systemName: reduceMotion ? arrow : "hand.point.up.left.fill")
                .font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                .shadow(color: .black, radius: 3)
                .position(x: center.x + (moved || reduceMotion ? 0.5 : -0.5) * vector.width,
                          y: center.y + (moved || reduceMotion ? 0.5 : -0.5) * vector.height)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85)) { moved = true }
        }
    }
}
