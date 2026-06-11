//ContentView.swift
import SwiftUI
import WatchKit

struct ContentView: View {
    @EnvironmentObject var viewModel: ScoreViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var lastPointChangeID = UUID()
    @State private var lastScoredPlayer: ScoreViewModel.Player? = nil
    @State private var highlightOpacity: Double = 0.3
    /// Player a vertical drag would currently score for, shown as a live
    /// preview (green = win, red = loss) so a wrong-direction swipe is visible
    /// before the finger lifts. nil = no preview.
    @State private var livePreviewTarget: ScoreViewModel.Player? = nil
    @AppStorage("hasCompletedFirstGame") private var hasCompletedFirstGame = false

    @Environment(\.appTheme) private var theme

    private var palette: ThemeColors { theme.colors }

    var isDeuceSide: Bool {
        // Perpetual Points doesn't care which service court the server is on —
        // pin the display to the deuce side so the server icon stays put.
        if viewModel.matchFormat.config.fixedDeuceSide { return true }
        if viewModel.sets.last?.isTieBreak == true {
            return viewModel.pointCountInTiebreak % 2 == 0
        } else {
            return (viewModel.currentPointsMe + viewModel.currentPointsOpponent) % 2 == 0
        }
    }

    var showCompassBadge: Bool {
        // Fixed-deuce-side formats (Perpetual Points) never change ends, so
        // the compass guidance would be misleading — suppress it entirely.
        guard !viewModel.matchFormat.config.fixedDeuceSide else { return false }
        return viewModel.checkChangeover && viewModel.isAtGameStart
    }

    var currentCourtBearing: Double? {
        guard let initial = viewModel.courtInitialHeading else { return nil }
        // No end changes in fixed-deuce-side formats — keep the bearing
        // pinned to the initial heading.
        guard !viewModel.matchFormat.config.fixedDeuceSide else { return initial }
        let isTiebreak = viewModel.sets.last?.isTieBreak == true
        // Changeovers happen after odd total games (1, 3, 5 …), so pairs of
        // games share one end. Count changeovers with ceil(gameCount/2), then
        // add one per 6-point tiebreak block which each trigger a changeover.
        let changeoverCount = (viewModel.gameCount + 1) / 2
            + (isTiebreak ? viewModel.pointCountInTiebreak / 6 : 0)
        let flip = changeoverCount % 2 == 1 ? 180.0 : 0.0
        return (initial + flip).truncatingRemainder(dividingBy: 360)
    }

    func triggerHighlight(for player: ScoreViewModel.Player?) {
        lastScoredPlayer = player

        // Token so a rapid follow-up point cancels this flash's pending second
        // pulse instead of letting the two overlap.
        let token = UUID()
        lastPointChangeID = token

        func pulse(fade: Double) {
            withAnimation(nil) { highlightOpacity = 0.95 }
            withAnimation(.easeInOut(duration: fade)) { highlightOpacity = 0.0 }
        }

        // Flash twice: a quick first blink, then a slower second blink that
        // lingers — making a registered point unmissable at a glance.
        pulse(fade: 0.45)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard lastPointChangeID == token else { return }
            pulse(fade: 1.1)
        }
    }

    /// True while a categorization sheet, changeover ack popup, the brief delay
    /// before that popup appears, or a doubles server decision is active —
    /// drag scoring is swallowed so the user can't double-score by accident.
    private var swipeScoringBlocked: Bool {
        viewModel.pendingStatPoint != nil
        || viewModel.pendingChangeoverAck != nil
        || viewModel.isChangeoverPending
        || (viewModel.needsDoublesTeamServerDecision && viewModel.gameCount > 0)
    }

    /// The player a vertical drag would award a point to if released now, or
    /// nil (horizontal swipe, sub-threshold, match over, or scoring blocked).
    /// Single source of truth shared by the live preview and the commit path
    /// so the previewed outcome can never disagree with the committed one.
    func pointTarget(for value: DragGesture.Value) -> ScoreViewModel.Player? {
        guard !swipeScoringBlocked, !viewModel.isMatchComplete() else { return nil }
        let h = value.translation.width
        let v = value.translation.height
        guard abs(h) <= abs(v) else { return nil }
        if v < -20 { return .me }
        if v > 20 { return .opponent }
        return nil
    }

    func handleSwipe(value: DragGesture.Value) {
        if swipeScoringBlocked { return }

        let horizontalAmount = value.translation.width
        let verticalAmount = value.translation.height

        if abs(horizontalAmount) > abs(verticalAmount) {
            if horizontalAmount < -20 {
                viewModel.undo()
                if let last = viewModel.lastScoredPlayer {
                    triggerHighlight(for: last)
                }
            } else if horizontalAmount > 40
                        && abs(horizontalAmount) > 2 * abs(verticalAmount)
                        && viewModel.statsTrackingEnabled
                        && (!viewModel.currentMatchStats.isEmpty || viewModel.matchStartTime != nil) {
                // Right-swipe → live stats. Higher threshold + horizontal bias
                // so it doesn't fire when the user overshoots a left-swipe undo.
                viewModel.showStatsView = true
            }
        } else if let target = pointTarget(for: value) {
            triggerHighlight(for: target)
            if target == .me {
                viewModel.winPoint(player: .me)
            } else {
                viewModel.losePoint(player: .me)
            }
        }
    }

    var body: some View {
        ZStack {
            if !hasCompletedFirstGame {
                VStack(spacing: 1) {
                    Text("↑ Win  ↓ Lose")
                    Text("← Undo  → Stats")
                }
                .font(.system(size: 9))
                .foregroundStyle(Color.gray.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 6)
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                // Scoreboard rows
                let isSuperTiebreakFormat = viewModel.isTiebreakOnlyFormat
                VStack(spacing: 6) {
                    scoreRow(for: .me)
                    scoreRow(for: .opponent)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.12))
                        )
                )
                .padding(.horizontal, 8)
                .frame(maxWidth: isSuperTiebreakFormat ? 200 : .infinity)
                // Scoped to the score display: a double-tap here flips the
                // 2nd-serve flag. Attaching at this level (not on ContentView
                // root) keeps single-tap responsiveness on the control buttons
                // below.
                .onTapGesture(count: 2) {
                    viewModel.toggleSecondServe()
                }

                if !viewModel.isMatchComplete() {
                    MomentumBadgeView(recentPoints: viewModel.history.suffix(8).map { $0.player })
                        .padding(.top, 4)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 4) {
                    // Show court view only if match is still in progress
                    if !viewModel.isMatchComplete() {
                        HStack(spacing: 6) {
                            CourtSideView(
                                isDeuceSide: isDeuceSide,
                                server: viewModel.currentServer,
                                centered: viewModel.matchFormat.config.fixedDeuceSide
                            )

                            ViewThatFits {
                                HStack(spacing: 6) {
                                    if showCompassBadge {
                                        CompassBadgeView(
                                            bearing: currentCourtBearing,
                                            currentHeading: viewModel.currentDeviceHeading,
                                            headingAccuracy: viewModel.currentHeadingAccuracy
                                        )
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.8)),
                                            removal: .opacity.combined(with: .scale(scale: 0.8))
                                        ))
                                    }
                                    HeartRateBadgeView(workoutManager: viewModel.workoutManager)
                                }
                                VStack(spacing: 6) {
                                    if showCompassBadge {
                                        CompassBadgeView(
                                            bearing: currentCourtBearing,
                                            currentHeading: viewModel.currentDeviceHeading,
                                            headingAccuracy: viewModel.currentHeadingAccuracy
                                        )
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.8)),
                                            removal: .opacity.combined(with: .scale(scale: 0.8))
                                        ))
                                    }
                                    HeartRateBadgeView(workoutManager: viewModel.workoutManager)
                                }
                            }
                            .animation(.easeInOut(duration: 0.5), value: showCompassBadge)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

                VStack(spacing: 4) {
                    if viewModel.isMatchComplete() {
                        let iWon = viewModel.matchWinner() == .me
                        let hasStats = viewModel.statsTrackingEnabled && !viewModel.currentMatchStats.isEmpty
                        VStack(spacing: 2) {
                            Text(iWon ? "You Won! 🏆" : "Opponent Won")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(iWon ? palette.me : Color.white.opacity(0.85))
                            Text("Match Complete")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if hasStats {
                                Label("Swipe for Stats", systemImage: "chart.bar")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill((iWon ? palette.meRow : palette.opponentRow).opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )

                        Button {
                            dismiss()
                            DispatchQueue.main.async {
                                viewModel.resetMatch()
                            }
                        } label: {
                            Label("End Match", systemImage: "checkmark.circle.fill")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    if !viewModel.isMatchComplete() && viewModel.sessionStartTime != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack(spacing: 4) {
                                Text("🔥 \(calorieBurnText)")
                                Text("·")
                                Text("🕐 \(formatDuration(viewModel.totalElapsedSeconds(at: context.date)))")
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(.top, 32)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Pre-warms .borderedProminent button shaders so the first real
            // sheet presentation has no stutter.
            PointCategorySheetPrewarm()
        }
        .contentShape(Rectangle())
        .focusable(true)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    livePreviewTarget = pointTarget(for: value)
                }
                .onEnded { value in
                    livePreviewTarget = nil
                    handleSwipe(value: value)
                }
        )
        // Categorization sheet: keyed off pendingStatPoint so a kill-mid-flow
        // re-presents it on relaunch (pendingStatPoint persists in AppState v2).
        .sheet(isPresented: pendingStatBinding) {
            if let pending = viewModel.pendingStatPoint {
                PointCategorySheet(pending: pending)
                    .environmentObject(viewModel)
                    .interactiveDismissDisabled(true)
            }
        }
        .sheet(isPresented: $viewModel.showStatsView) {
            MatchStatsView(stats: viewModel.currentMatchStats,
                           setScores: viewModel.sets,
                           title: viewModel.isMatchComplete() ? "Match Stats" : "Live Stats",
                           matchType: viewModel.matchType,
                           matchFormat: viewModel.matchFormat,
                           matchIsComplete: viewModel.isMatchComplete(),
                           setElapsedSeconds: viewModel.setElapsedSeconds,
                           currentSetSessionStart: viewModel.currentSetSessionStart)
        }
        .onChange(of: viewModel.sets) { _ in
            // Hide tooltip once a game is won or the match ends (covers tiebreak-only formats
            // where gameCount stays 0). resetMatch resets both conditions → tooltip reappears.
            hasCompletedFirstGame = viewModel.gameCount > 0 || viewModel.isMatchComplete()
        }
        .overlay {
            if let info = viewModel.pendingChangeoverAck {
                ChangeoverAckOverlay(info: info) {
                    viewModel.acknowledgeChangeover()
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: viewModel.pendingChangeoverAck != nil)
            }
        }
        .overlay {
            if viewModel.needsDoublesTeamServerDecision && viewModel.gameCount > 0 {
                DoublesTeamServerDecisionOverlay { server in
                    viewModel.resolveDoublesTeamServer(server)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: viewModel.needsDoublesTeamServerDecision)
            }
        }
    }

    private var pendingStatBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingStatPoint != nil },
            set: { newValue in
                // SwiftUI dismisses the inner sheet when the outer match sheet
                // is pulled down. Drop the queued changeover announcement in
                // lock-step so `isChangeoverPending` can't get stuck blocking
                // swipes invisibly.
                if !newValue { viewModel.discardPendingStatCategorization() }
            }
        )
    }

    private var scoreboardSets: [(index: Int, set: ScoreViewModel.SetScore)] {
        viewModel.visibleSets().enumerated().compactMap { entry in
            let index = entry.offset
            let set = entry.element
            // Perpetual tiebreak: show only the last 3 tiebreaks to
            // avoid horizontal overflow on the narrow Watch display.
            if viewModel.matchFormat == .perpetualSuperTiebreak {
                guard index >= viewModel.sets.count - 3 else { return nil }
                return (index: index, set: set)
            }
            let isThirdSet = viewModel.sets.count == 3 && index == 2
            // Hide the super-tiebreak deciding set from the scoreboard until complete;
            // it is shown live via the point badge instead.
            let hideSuperTBBeforeComplete = isThirdSet && set.isTieBreak && !viewModel.isMatchComplete()
            // Only hide a non-tiebreak third set when the format expects that slot to be
            // a super-tiebreak (i.e. .standard). For .bestOf3FullFinalSet the third set
            // is a regular set and must always be visible.
            let hideRegularThirdSet = isThirdSet && !set.isTieBreak &&
                viewModel.matchFormat.config.finalSetStyle == .superTiebreak
            guard !(hideSuperTBBeforeComplete || hideRegularThirdSet) else { return nil }
            return (index: index, set: set)
        }
    }

    @ViewBuilder
    private func scoreRow(for player: ScoreViewModel.Player) -> some View {
        let isMe = player == .me

        HStack(spacing: 4) {
            serverIndicator(for: player)
                .frame(width: viewModel.matchType == .doubles ? 34 : 20)

            Text(isMe ? "Me" : "Op")
                .font(.headline)
                .frame(width: 30, alignment: .leading)

            ForEach(scoreboardSets, id: \.index) { index, set in
                scoreCell(for: player, index: index, set: set)
            }

            if !viewModel.isMatchComplete() && !viewModel.isTiebreakOnlyFormat {
                pointBadge(for: player)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rowBackground(for: player))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12))
                )
        )
        // Live preview: the row that will receive the point lights up green (a
        // win for me) or red (a loss) while the finger is still down.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .fill((player == .me ? Color.green : Color.red)
                    .opacity(livePreviewTarget == player ? 0.22 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(livePreviewTarget == player
                            ? (player == .me ? Color.green : Color.red)
                            : .clear,
                        lineWidth: 3)
        )
        .animation(.easeOut(duration: 0.12), value: livePreviewTarget)
    }

    @ViewBuilder
    private func serverIndicator(for player: ScoreViewModel.Player) -> some View {
        let isServer = viewModel.currentServer == player
        let showSecondBadge = isServer && viewModel.isOnSecondServe
        let isDoubles = viewModel.matchType == .doubles
        let doublesLabel: String? = isDoubles && isServer ? viewModel.doublesServer?.displayName : nil

        Group {
            if isServer {
                ZStack {
                    Text("🎾")
                        .font(.system(size: 16))
                    if let label = doublesLabel {
                        Text(label)
                            .font(.system(size: 7, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 2)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                            .offset(y: 8)
                    }
                }
                .frame(width: 32, height: 22)
                .accessibilityLabel(showSecondBadge ? "Serving, second serve" : "Serving")
            } else {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.6), lineWidth: 0.5)
                    )
                    .opacity(0.35)
                    .accessibilityLabel("Not serving")
            }
        }
        .overlay(alignment: .topTrailing) {
            if showSecondBadge {
                Text("2")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 10, height: 10)
                    .background(Circle().fill(Color.yellow))
                    .offset(x: 4, y: -4)
            }
        }
    }

    @ViewBuilder
    private func scoreCell(for player: ScoreViewModel.Player, index: Int, set: ScoreViewModel.SetScore) -> some View {
        let isActive = index == viewModel.sets.count - 1
        let isSuperTiebreakMatch = viewModel.isTiebreakOnlyFormat
        let isSuperTB = set.isTieBreak && viewModel.sets.count == 3 && index == 2
        let showSuperTB = !(isSuperTB && !viewModel.isMatchComplete())
        let games = player == .me ? set.gamesMe : set.gamesOpponent
        let tiebreakPoints = player == .me ? set.tieBreakPointsMe : set.tieBreakPointsOpponent

        if isSuperTiebreakMatch {
            scorePill(width: 24, isActive: isActive, player: player) {
                Text("\(tiebreakPoints)")
                    .font(.headline)
            }
        } else if isSuperTB && showSuperTB {
            scorePill(width: 24, isActive: isActive, player: player) {
                Text("\(tiebreakPoints)")
                    .font(.headline)
            }
        } else {
            let showTiebreak = set.isTieBreak && tiebreakPoints > 0 && !isActive
            let pillWidth: CGFloat = showTiebreak ? 34 : 24
            scorePill(width: pillWidth, isActive: isActive, player: player) {
                HStack(spacing: 2) {
                    Text("\(games)")
                        .frame(width: 14, alignment: .trailing)
                    if showTiebreak {
                        Text("\(tiebreakPoints)")
                            .font(.system(size: 8))
                            .baselineOffset(6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pointBadge(for player: ScoreViewModel.Player) -> some View {
        let flashColor = player == .me ? palette.me : palette.opponent
        Text(viewModel.displayedScore(for: player))
            .font(.body.weight(.semibold))
            .frame(width: 32, alignment: .trailing)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(cellBackground(for: player, isActive: true).opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(flashColor.opacity(lastScoredPlayer == player ? highlightOpacity : 0))
                    )
            )
    }

    @ViewBuilder
    private func scorePill<Content: View>(width: CGFloat, isActive: Bool, player: ScoreViewModel.Player, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(cellBackground(for: player, isActive: isActive))
            )
    }

    private func rowBackground(for player: ScoreViewModel.Player) -> Color {
        (player == .me ? palette.meRow : palette.opponentRow).opacity(0.55)
    }

    private func cellBackground(for player: ScoreViewModel.Player, isActive: Bool) -> Color {
        if isActive {
            return player == .me ? palette.me.opacity(0.8) : palette.opponent.opacity(0.85)
        } else {
            return Color.white.opacity(0.14)
        }
    }

    private var calorieBurnText: String {
        let kilocalories = viewModel.workoutManager.totalKilocalories
            .map { Int($0.rounded()) }
        let value = kilocalories.map { $0.formatted(.number.grouping(.automatic)) } ?? "--"
        return "\(value) kcal"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSecs = max(0, Int(seconds))
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        let hours = mins / 60
        let remMins = mins % 60
        if hours > 0 {
            return "\(hours) h \(remMins) m \(secs) s"
        }
        return "\(mins) m \(secs) s"
    }
}

// MARK: - MomentumBadgeView

struct MomentumBadgeView: View {
    /// Up to 8 recent point winners, oldest first.
    let recentPoints: [ScoreViewModel.Player]

    @Environment(\.appTheme) private var theme
    private var p: ThemeColors { theme.colors }

    private let totalSlots = 8

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSlots, id: \.self) { i in
                let filledIndex = i - (totalSlots - recentPoints.count)
                RoundedRectangle(cornerRadius: 2)
                    .fill(dashColor(filledIndex: filledIndex))
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12))
                )
        )
    }

    private func dashColor(filledIndex: Int) -> Color {
        guard filledIndex >= 0, filledIndex < recentPoints.count else {
            return Color.white.opacity(0.15)
        }
        return recentPoints[filledIndex] == .me ? p.me : p.opponent
    }
}

struct HeartRateBadgeView: View {
    @ObservedObject var workoutManager: WorkoutManager

    private enum HeartRateBand {
        case low, moderate, high, max

        var color: Color {
            switch self {
            case .low: return .green
            case .moderate: return .yellow
            case .high: return .orange
            case .max: return .red
            }
        }
    }

    var body: some View {
        let heartRate = workoutManager.currentHeartRate
        let bpmText = heartRate.map { "\(Int($0.rounded()))" } ?? "--"
        VStack(spacing: 1) {
            Text("❤️")
                .font(.system(size: 9))
            Text(bpmText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(heartRateColor)
            Text("BPM")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(width: 38)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(heartRateColor.opacity(0.7), lineWidth: 1)
                )
        )
    }

    private var heartRateColor: Color {
        guard let heartRate = workoutManager.currentHeartRate else { return .white.opacity(0.6) }
        return band(for: heartRate).color
    }

    private func band(for heartRate: Double) -> HeartRateBand {
        switch heartRate {
        case 170...:
            return .max
        case 150..<170:
            return .high
        case 120..<150:
            return .moderate
        default:
            return .low
        }
    }
}

// MARK: - CompassBadgeView

struct CompassBadgeView: View {
    let bearing: Double?
    let currentHeading: Double?
    let headingAccuracy: Double

    var body: some View {
        VStack(spacing: 2) {
            Text("🧭")
                .font(.system(size: 9))
            if let bearing = bearing {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(guidanceArrowRotation(for: bearing)))
                    .animation(.easeInOut(duration: 0.4), value: guidanceArrowRotation(for: bearing))
                Text(cardinalLabel(for: bearing))
                    .font(.system(size: 8, weight: .medium))
            } else {
                Image(systemName: "location.slash")
                    .font(.system(size: 13))
                Text("--")
                    .font(.system(size: 8, weight: .medium))
            }
        }
        .foregroundStyle(compassColor)
        .animation(.easeInOut(duration: 0.3), value: compassColor == .green)
        .frame(width: 38)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(compassColor.opacity(0.7), lineWidth: 1)
                )
        )
    }


    private func guidanceArrowRotation(for targetBearing: Double) -> Double {
        guard let liveHeading = currentHeading else {
            // Without a live heading, fall back to absolute bearing so the user
            // still sees where north/court heading sits on the compass.
            return targetBearing
        }

        // Rotate the arrow relative to the direction the player is currently
        // facing: straight up means "you are on heading", otherwise arrow
        // points to where the player should turn next.
        let delta = targetBearing - liveHeading
        return normalizedAngle(delta)
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let wrapped = angle.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { return wrapped - 360 }
        if wrapped < -180 { return wrapped + 360 }
        return wrapped
    }
    private var compassColor: Color {
        guard let bearing = bearing,
              let live = currentHeading,
              headingAccuracy >= 0,
              headingAccuracy <= 30 else {
            return Color.white.opacity(0.5)
        }
        let diff = min(abs(live - bearing), 360 - abs(live - bearing))
        if diff <= 45  { return .green }
        if diff >= 135 { return .red }
        return .orange
    }

    private func cardinalLabel(for bearing: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return dirs[Int((bearing + 22.5) / 45) % 8]
    }
}

// MARK: - CourtSideView

struct CourtSideView: View {
    let isDeuceSide: Bool
    let server: ScoreViewModel.Player?
    var centered: Bool = false

    @Environment(\.appTheme) private var theme
    private var p: ThemeColors { theme.colors }

    var body: some View {
        VStack(spacing: 6) {
            playerRow(isMe: false) // Opponent on top
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.55))
            playerRow(isMe: true)  // Me on bottom
        }
        .frame(width: 52)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(courtFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(courtStrokeColor, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func playerRow(isMe: Bool) -> some View {
        let isServer = (isMe && server == .me) || (!isMe && server == .opponent)
        let isReceiver = !isServer && server != nil
        let isLeftSide = isServer ? serverOnLeft : !serverOnLeft

        HStack(spacing: 0) {
            Spacer()
                .frame(width: centered ? 14 : (isLeftSide ? 0 : 26))

            playerDot(isServer: isServer, isReceiver: isReceiver)

            Spacer()
                .frame(width: centered ? 14 : (isLeftSide ? 26 : 0))
        }
        .frame(height: 14)
        .animation(.easeInOut(duration: 0.5), value: isLeftSide)
    }

    private var serverOnLeft: Bool {
        guard let server = server else { return false }
        if server == .me {
            return !isDeuceSide
        } else {
            return isDeuceSide // Opponent’s right = screen-left
        }
    }

    @ViewBuilder
    private func playerDot(isServer: Bool, isReceiver: Bool) -> some View {
        let fillColor = dotColor(isServer: isServer, isReceiver: isReceiver)

        Circle()
            .fill(fillColor)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: isServer ? p.server.opacity(0.6) : Color.clear, radius: 3, x: 0, y: 0)
    }

    private func dotColor(isServer: Bool, isReceiver: Bool) -> Color {
        if isServer {
            return p.server
        } else if isReceiver {
            return Color(red: 0.70, green: 0.83, blue: 1.00)
        } else {
            return Color.white.opacity(0.6)
        }
    }

    private var courtFillColor: Color {
        switch server {
        case .me:       return p.meCourt
        case .opponent: return p.opponentCourt
        case .none:     return p.neutralCourt
        }
    }

    private var courtStrokeColor: Color {
        switch server {
        case .me:       return p.meCourtStroke
        case .opponent: return p.opponentCourtStroke
        case .none:     return p.neutralCourtStroke
        }
    }
}




struct ChangeoverAckOverlay: View {
    let info: ChangeoverInfo
    let onAck: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
            VStack(spacing: 6) {
                Text(info.symbol)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(info.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onAck) {
                    Text("OK")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
        }
    }
}

struct DoublesTeamServerDecisionOverlay: View {
    let onSelect: (ScoreViewModel.DoublesServer) -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Who serves next?")
                    .font(.headline.weight(.bold))
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Button("Me") { onSelect(.me) }
                        .buttonStyle(HomeButtonStyle(background: theme.colors.buttonServerMe))
                    Button("Partner") { onSelect(.partner) }
                        .buttonStyle(HomeButtonStyle(background: theme.colors.buttonServerMe))
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ScoreViewModel())
    }
}
