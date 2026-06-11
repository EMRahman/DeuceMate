// LiveScoreboardView.swift — Full-screen landscape scoreboard, readable from ~3 m.
import SwiftUI
import DeuceMateCore

// MARK: - PhoneMomentumBadgeView

private struct PhoneMomentumBadgeView: View {
    let recentPoints: [Player]
    let meColor: Color
    let oppColor: Color

    private let totalSlots = 8

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSlots, id: \.self) { i in
                let filledIndex = i - (totalSlots - recentPoints.count)
                RoundedRectangle(cornerRadius: 3)
                    .fill(dashColor(filledIndex: filledIndex))
                    .frame(width: 28, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12))
                )
        )
    }

    private func dashColor(filledIndex: Int) -> Color {
        guard filledIndex >= 0, filledIndex < recentPoints.count else {
            return Color.white.opacity(0.15)
        }
        return recentPoints[filledIndex] == .me ? meColor : oppColor
    }
}

struct LiveScoreboardView: View {
    @EnvironmentObject private var store: PhoneStatsStore
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @AppStorage("iPhoneInputEnabled") private var iPhoneInputEnabled: Bool = false
    /// Mirrors the watch's `statsTrackingEnabled` (synced via WatchConnectivity).
    /// When off the watch never produces a `pendingPoint`, but we read it
    /// locally to control the ending-shot phase of the panel.
    @AppStorage("statsTrackingEnabled") private var statsTrackingEnabled: Bool = false
    /// Monotonic uptime of the last accepted swipe (`ProcessInfo.systemUptime`),
    /// so wall-clock changes (NTP sync, manual time adjustment) can't unblock or
    /// stretch the 0.25 s debounce window.
    @State private var lastSwipeUptime: TimeInterval? = nil
    /// Player a vertical drag would currently score for: true = ME (a win),
    /// false = OPP (a loss), nil = no preview. Drives the live row highlight.
    @State private var livePreviewWinsMe: Bool? = nil

    private var meColor:     Color { theme.colors.me }
    private var oppColor:    Color { theme.colors.opponent }
    private var serverColor: Color { theme.colors.server }
    private static let dimWhite = Color.white.opacity(0.45)
    private static let boardBg  = Color(white: 0.07)
    /// Debounce window for accepted swipes — shared by `handleSwipe` (enforced
    /// on release) and `livePreviewTarget` (suppresses the preview while a
    /// release would be swallowed). They must stay in sync.
    private static let swipeDebounceInterval: TimeInterval = 0.25

    // Space reserved for the top chrome (LIVE + close) and bottom format label.
    private static let chromeTop: CGFloat = 44
    // When the momentum badge is shown it adds ~20 pt above the format label.
    private func showMomentum(for record: MatchRecord) -> Bool {
        !record.recentPoints.isEmpty
    }
    private func chromeBot(for record: MatchRecord) -> CGFloat { showMomentum(for: record) ? 52 : 28 }

    private var record: MatchRecord? {
        guard let id = syncService.activeMatchID else { return nil }
        return store.history.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let record {
                GeometryReader { geo in
                    // Compute row height from space that isn't covered by the chrome overlay.
                    let available = geo.size.height - Self.chromeTop - chromeBot(for: record)
                    let rowHeight = available / 2
                    let completedSets = Array(record.setScores.dropLast())
                    let currentSet   = record.setScores.last
                    let inTiebreak   = currentSet?.isTieBreak == true

                    VStack(spacing: 0) {
                        playerRow(
                            label: "ME",
                            color: meColor,
                            isServing: record.currentServer == .me,
                            isOnSecondServe: record.isOnSecondServe,
                            completedSets: completedSets,
                            currentSet: currentSet,
                            inTiebreak: inTiebreak,
                            gamePoints: record.currentPointsMe,
                            opponentPoints: record.currentPointsOpponent,
                            forMe: true,
                            rowHeight: rowHeight,
                            totalWidth: geo.size.width
                        )

                        Divider()
                            .overlay(Color.white.opacity(0.15))

                        playerRow(
                            label: "OPP",
                            color: oppColor,
                            isServing: record.currentServer == .opponent,
                            isOnSecondServe: record.isOnSecondServe,
                            completedSets: completedSets,
                            currentSet: currentSet,
                            inTiebreak: inTiebreak,
                            gamePoints: record.currentPointsMe,
                            opponentPoints: record.currentPointsOpponent,
                            forMe: false,
                            rowHeight: rowHeight,
                            totalWidth: geo.size.width
                        )
                    }
                    .background(Self.boardBg)
                    // Push rows clear of the chrome overlays.
                    .padding(.top, Self.chromeTop)
                    .padding(.bottom, chromeBot(for: record))
                }

                // Chrome overlay — costs no vertical space in the layout.
                VStack {
                    HStack(alignment: .top) {
                        liveBadge
                        Spacer()
                        closeButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                    Spacer()

                    VStack(spacing: 4) {
                        if showMomentum(for: record) {
                            PhoneMomentumBadgeView(
                                recentPoints: record.recentPoints,
                                meColor: meColor,
                                oppColor: oppColor
                            )
                        }
                        Text(formatLabel(for: record))
                            .font(.footnote)
                            .foregroundStyle(Self.dimWhite)
                        if iPhoneInputEnabled {
                            Text("↑ Me   ↓ Opp   ← Undo")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                    }
                    .padding(.bottom, 10)
                }

                // Post-point categorization panel. Only surfaces when iPhone
                // Input is on (the watch ignores stat-actions otherwise, so a
                // panel without working buttons would just be confusing).
                // Wrapped in an always-present Group so the panel's
                // `.transition` actually fires — the `.animation` modifiers
                // must live on a container that stays in the hierarchy.
                Group {
                    if iPhoneInputEnabled,
                       let pending = syncService.pendingPoint {
                        VStack {
                            Spacer()
                            LivePointCategoryPanel(
                                pending: pending,
                                outcome: syncService.pendingPointOutcome,
                                detailedShotTrackingEnabled: statsTrackingEnabled,
                                onSelectOutcome: { outcome in
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    syncService.sendSelectOutcome(outcome)
                                },
                                onCommitEndingShot: { shot in
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    syncService.sendCommitEndingShot(shot)
                                },
                                onCancelOutcome: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    syncService.sendCancelOutcomeSelection()
                                },
                                onUndoPoint: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    syncService.sendUndoPoint()
                                }
                            )
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .animation(.easeOut(duration: 0.22), value: syncService.pendingPoint)
                .animation(.easeInOut(duration: 0.18), value: syncService.pendingPointOutcome)

            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("Match ended")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Button("Close") { closeAndRestorePortrait() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    livePreviewWinsMe = livePreviewTarget(for: value)
                }
                .onEnded { value in
                    livePreviewWinsMe = nil
                    handleSwipe(value: value)
                }
        )
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            lockLandscape()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            restorePortrait()
        }
    }

    // MARK: - Swipe input (iPhone Input)

    /// Translate a drag value into a single score command and forward it to the
    /// watch. The watch remains the source of truth — it validates, applies via
    /// its existing `winPoint` / `losePoint` / `undo` paths, persists atomically,
    /// and pushes the resulting record back. Debounced so a single fast flick
    /// can't double-fire.
    ///
    /// Direction mapping matches the watch swipe handler (ContentView.handleSwipe):
    ///   up    → Me wins point   (dy < 0)
    ///   down  → Opponent wins   (dy > 0)
    ///   left  → Undo last point (dx < 0)
    /// Right-swipe is intentionally a no-op here: the iPhone scoreboard has no
    /// in-scene stats sheet (stats live in the past-matches detail), so a right
    /// swipe shouldn't accidentally trigger anything.
    private func handleSwipe(value: DragGesture.Value) {
        guard iPhoneInputEnabled else { return }
        // Mirror the watch's swipe guard: while a categorization is pending we
        // can't safely score another point. The watch rejects the command
        // anyway, but blocking locally avoids confusing the user with a
        // no-op swipe and an unchanged scoreboard.
        if syncService.pendingPoint != nil { return }
        // Use the displayed record's id rather than `syncService.activeMatchID`:
        // they track the same value in steady state, but the displayed record
        // is what the spectator can actually see and is therefore the only
        // safe scope to score against. The watch rejects commands whose id
        // doesn't match its own current live match identity.
        guard let displayedMatchID = record?.id else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastSwipeUptime, now - last < Self.swipeDebounceInterval { return }

        // The DragGesture already enforces a 30 pt minimum, so by the time we
        // get here the swipe is large enough — pick the dominant axis.
        let dx = value.translation.width
        let dy = value.translation.height
        let absX = abs(dx)
        let absY = abs(dy)

        let command: String
        if absY >= absX {
            command = dy < 0 ? MatchSyncKey.scoreCommandWinMe : MatchSyncKey.scoreCommandWinOpp
        } else if dx < 0 {
            command = MatchSyncKey.scoreCommandUndo
        } else {
            return
        }

        lastSwipeUptime = now
        let style: UIImpactFeedbackGenerator.FeedbackStyle =
            (command == MatchSyncKey.scoreCommandUndo) ? .light : .medium
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        syncService.sendScoreCommand(command, matchID: displayedMatchID)
    }

    /// The player a vertical drag would award a point to if released now:
    /// true = ME, false = OPP, nil = horizontal swipe (undo) or input disabled.
    /// Mirrors `handleSwipe`'s direction logic *and* its debounce so the live
    /// preview can never promise a point the release won't commit. Deliberately
    /// avoids reading `record` (an O(N) history scan) to stay cheap on the drag
    /// hot path — with no live match the player rows aren't rendered, so a
    /// stray preview value simply has nothing to highlight.
    private func livePreviewTarget(for value: DragGesture.Value) -> Bool? {
        guard iPhoneInputEnabled, syncService.pendingPoint == nil else { return nil }
        if let last = lastSwipeUptime,
           ProcessInfo.processInfo.systemUptime - last < Self.swipeDebounceInterval {
            return nil
        }
        let dx = value.translation.width
        let dy = value.translation.height
        guard abs(dy) >= abs(dx) else { return nil }
        return dy < 0
    }

    // MARK: - Orientation

    private func closeAndRestorePortrait() {
        restorePortrait()
        dismiss()
    }

    private func foregroundScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func lockLandscape() {
        AppDelegate.orientationLock = .landscape
        foregroundScene()?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
    }

    private func restorePortrait() {
        AppDelegate.orientationLock = .portrait
        foregroundScene()?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }

    // MARK: - Chrome

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
            Text("LIVE")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.red)
                .kerning(1.5)
        }
    }

    private var closeButton: some View {
        Button { closeAndRestorePortrait() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    // MARK: - Player row

    @ViewBuilder
    private func playerRow(
        label: String,
        color: Color,
        isServing: Bool,
        isOnSecondServe: Bool,
        completedSets: [SetScore],
        currentSet: SetScore?,
        inTiebreak: Bool,
        gamePoints: Int,
        opponentPoints: Int,
        forMe: Bool,
        rowHeight: CGFloat,
        totalWidth: CGFloat
    ) -> some View {
        let nameWidth  = totalWidth * 0.12
        let dotSize    = rowHeight * 0.08
        let oldSetFont = rowHeight * 0.55
        let curSetFont = rowHeight * 0.65
        let gameFont   = rowHeight * 0.80
        let nameFont   = rowHeight * 0.22

        HStack(spacing: 0) {
            // Player label + serving dot (+ "2" badge on second serve)
            HStack(spacing: dotSize * 0.6) {
                Text(label)
                    .font(.system(size: nameFont, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if isServing {
                    Circle()
                        .fill(serverColor)
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: serverColor.opacity(0.8), radius: dotSize * 0.5)
                    if isOnSecondServe {
                        Text("2")
                            .font(.system(size: dotSize * 1.4, weight: .heavy, design: .monospaced))
                            .foregroundStyle(serverColor)
                            .fixedSize()
                            .frame(width: 0, alignment: .leading)
                    }
                } else {
                    Spacer().frame(width: dotSize)
                }
            }
            .frame(width: nameWidth, alignment: .leading)
            .padding(.leading, 16)

            // Completed set scores
            ForEach(completedSets.indices, id: \.self) { i in
                let set = completedSets[i]
                let n = set.isTieBreak
                    ? (forMe ? set.tieBreakPointsMe : set.tieBreakPointsOpponent)
                    : (forMe ? set.gamesMe : set.gamesOpponent)
                Text("\(n)")
                    .font(.system(size: oldSetFont, weight: .bold, design: .monospaced))
                    .foregroundStyle(color.opacity(0.60))
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }

            // Current set score
            if let current = currentSet {
                let n = current.isTieBreak
                    ? (forMe ? current.tieBreakPointsMe : current.tieBreakPointsOpponent)
                    : (forMe ? current.gamesMe : current.gamesOpponent)
                Text("\(n)")
                    .font(.system(size: curSetFont, weight: .heavy, design: .monospaced))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }

            // Game score (regular sets only)
            if !inTiebreak {
                let me  = gamePoints
                let opp = opponentPoints
                let isDeuce = me >= 3 && opp >= 3 && me == opp
                let scoreLabel = tennisLabel(me: me, opp: opp, forMe: forMe)
                Text(scoreLabel)
                    .font(.system(size: gameFont, weight: .heavy, design: .monospaced))
                    .foregroundStyle(isDeuce ? serverColor : color)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Live preview: highlight the row that will receive the point —
        // green for a win (ME), red for a loss (OPP).
        .background((forMe ? Color.green : Color.red)
            .opacity(livePreviewWinsMe == forMe ? 0.25 : 0))
        .overlay(
            Rectangle().stroke(forMe ? Color.green : Color.red,
                               lineWidth: livePreviewWinsMe == forMe ? 4 : 0)
        )
        .animation(.easeOut(duration: 0.12), value: livePreviewWinsMe)
    }

    // MARK: - Helpers

    private func tennisLabel(me: Int, opp: Int, forMe: Bool) -> String {
        if me >= 3 && opp >= 3 {
            if me == opp { return "40" }
            let meLeading = me > opp
            return (forMe ? meLeading : !meLeading) ? "AD" : "40"
        }
        let labels = ["0", "15", "30", "40"]
        let pts = forMe ? me : opp
        return pts < labels.count ? labels[pts] : "\(pts)"
    }

    private func formatLabel(for record: MatchRecord) -> String {
        var parts: [String] = []
        switch record.matchFormat {
        case .standard:               parts.append("Best of 3")
        case .bestOf3FullFinalSet:    parts.append("Best of 3 (Full Final Set)")
        case .superTiebreak:          parts.append("Super Tiebreak")
        case .perpetualSuperTiebreak: parts.append("Perpetual Tiebreak")
        case .quick4Games:            parts.append("Quick 4 Games")
        case .perpetualPoints:        parts.append("Perpetual Points")
        }
        parts.append(record.matchType == .doubles ? "Doubles" : "Singles")
        return parts.joined(separator: " · ")
    }
}
