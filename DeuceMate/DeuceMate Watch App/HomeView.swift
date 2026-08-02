import SwiftUI
import DeuceMateCore
import WatchKit
import CoreLocation

private enum ButtonGradients {
    static let guide = LinearGradient(
        colors: [
            Color(red: 0.27, green: 0.32, blue: 0.41),
            Color(red: 0.14, green: 0.18, blue: 0.25)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let end = LinearGradient(
        colors: [
            Color(red: 0.90, green: 0.27, blue: 0.33),
            Color(red: 0.75, green: 0.17, blue: 0.22)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let support = LinearGradient(
        colors: [
            Color(red: 0.56, green: 0.36, blue: 0.92),
            Color(red: 0.42, green: 0.28, blue: 0.70)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct RootView: View {
    @EnvironmentObject var viewModel: ScoreViewModel

    var body: some View {
        HomeView()
    }
}

struct RootModal: View {
    @EnvironmentObject var viewModel: ScoreViewModel
    @State private var warmupComplete: Bool = false
    @State private var matchTypeChosen: Bool = false
    @State private var courtSideConfirmed: Bool = false
    @State private var confirmButtonForced: Bool = false

    private static let headingConfirmTimeoutSeconds: TimeInterval = 15

    /// Set the match start timestamp only when this is genuinely a new match.
    /// Guard prevents reopening RootModal mid-match (to change servers) from
    /// resetting the clock. All three predicates must hold: no clock yet, no
    /// stats accumulated, and no point history.
    private func startMatchTimerIfNeeded() {
        if viewModel.matchStartTime == nil
            && viewModel.currentMatchStats.isEmpty
            && viewModel.history.isEmpty {
            let now = Date()
            viewModel.matchStartTime = now
            viewModel.sessionStartTime = now
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if !warmupComplete {
                VStack(spacing: 20) {
                    Image(systemName: "figure.tennis")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("Warming Up")
                        .font(.headline)
                        .foregroundColor(.white)
                    Button("Warm Up Complete") {
                        viewModel.beginMatchSession()
                        warmupComplete = true
                    }
                    .font(.headline)
                    .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonPrimary))
                }
            } else if !matchTypeChosen {
                VStack(spacing: 16) {
                    Text("Match Type")
                        .font(.headline)
                        .foregroundColor(.white)
                    HStack(spacing: 12) {
                        Button("Singles") {
                            viewModel.matchType = .singles
                            matchTypeChosen = true
                        }
                        .font(.subheadline)
                        .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonPrimary))
                        Button("Doubles") {
                            viewModel.matchType = .doubles
                            matchTypeChosen = true
                        }
                        .font(.subheadline)
                        .buttonStyle(HomeButtonStyle(background: ButtonGradients.support))
                    }
                }
            } else if viewModel.currentServer == nil {
                if viewModel.matchType == .doubles {
                    doublesServerSelectionView
                } else {
                    singlesServerSelectionView
                }
            } else if viewModel.checkChangeover
                        && !courtSideConfirmed
                        && !viewModel.matchFormat.config.fixedDeuceSide
                        && CLLocationManager.headingAvailable() {
                courtSideConfirmationView
            } else {
                VStack(spacing: 4) {
                    Spacer(minLength: 20)
                    ContentView()
                    Spacer(minLength: 40)
                }
            }
        }
        .onAppear {
            if viewModel.currentServer != nil {
                warmupComplete = true
                matchTypeChosen = true
                // Only skip confirmation if the heading was already locked (or
                // the feature is off). If the sheet was dismissed mid-confirmation
                // before lockInitialHeading() ran, courtInitialHeading is still
                // nil and the confirmation screen must be shown again.
                if !viewModel.checkChangeover
                    || viewModel.matchFormat.config.fixedDeuceSide
                    || viewModel.courtInitialHeading != nil {
                    courtSideConfirmed = true
                }
                if viewModel.checkChangeover {
                    viewModel.startHeadingMonitoring()
                }
            } else if viewModel.isTiebreakOnlyFormat {
                // Quick Super Tiebreak / Perpetual Tiebreak skips the warmup
                // screen; jump straight to match-type / server selection.
                warmupComplete = true
                viewModel.beginMatchSession()
            }
        }
        .onDisappear {
            // Sheet dismissed before server was chosen — no match started, stop any session.
            if viewModel.currentServer == nil {
                viewModel.workoutManager.stopWorkout()
            }
        }
    }

    /// Common server-selection commit step. Starts the match clock and seeds
    /// the tiebreak rotation for super-tiebreak-only matches.
    private func commitServerSelection() {
        viewModel.startHeadingMonitoring()
        if !viewModel.checkChangeover
            || viewModel.matchFormat.config.fixedDeuceSide
            || !CLLocationManager.headingAvailable() {
            startMatchTimerIfNeeded()
            viewModel.syncMatchStart()
        }
        if viewModel.isTiebreakOnlyFormat {
            viewModel.prepareTiebreakOnlySet()
        }
    }

    private var headingReadyForLock: Bool {
        (viewModel.currentDeviceHeading != nil
            && viewModel.currentHeadingAccuracy >= 0
            && viewModel.currentHeadingAccuracy <= 45)
        || confirmButtonForced
    }

    private var courtSideConfirmationView: some View {
        VStack(spacing: 16) {
            Text("Correct court side?")
                .font(.headline)
                .foregroundColor(.white)

            Text("Stand on your starting end.")
                .font(.footnote)
                .foregroundColor(.secondary)

            if viewModel.currentDeviceHeading != nil {
                Text("Accuracy: ±\(Int(viewModel.currentHeadingAccuracy))°")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text("Hold watch up… acquiring heading")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Button("✓ Confirmed") {
                viewModel.lockInitialHeading()
                startMatchTimerIfNeeded()
                viewModel.syncMatchStart()
                // Set confirmed first so SwiftUI can begin the transition
                // immediately. headingReadyForLock being true guarantees
                // lockInitialHeading succeeded or confirmButtonForced is set.
                courtSideConfirmed = true
            }
            .font(.headline)
            .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonPrimary))
            .disabled(!headingReadyForLock)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.headingConfirmTimeoutSeconds) {
                confirmButtonForced = true
            }
        }
    }

    private var singlesServerSelectionView: some View {
        VStack(spacing: 20) {
            Text("Who is serving first?")
                .font(.headline)
                .foregroundColor(.white)
            HStack(spacing: 12) {
                Button("Me") {
                    viewModel.currentServer = .me
                    commitServerSelection()
                }
                .font(.headline)
                .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonServerMe))
                Button("Opponent") {
                    viewModel.currentServer = .opponent
                    commitServerSelection()
                }
                .font(.headline)
                .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonServerOpponent))
            }
        }
    }

    private var doublesServerSelectionView: some View {
        VStack(spacing: 12) {
            Text("Who serves first?")
                .font(.headline)
                .foregroundColor(.white)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Me") {
                        viewModel.startDoublesMatch(firstServer: .me)
                        commitServerSelection()
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonServerMe))
                    Button("Partner") {
                        viewModel.startDoublesMatch(firstServer: .partner)
                        commitServerSelection()
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonServerMe))
                }
                Button("Opponent") {
                    viewModel.startDoublesMatch(firstServer: .opponentS1)
                    commitServerSelection()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonServerOpponent))
            }
        }
    }
}

private struct BirthYearPickerView: View {
    let selectedYear: Int
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    private let maxYear = Calendar.current.component(.year, from: Date())

    var body: some View {
        List {
            Button {
                onSelect(0)
                dismiss()
            } label: {
                HStack {
                    Text("Skip")
                    Spacer()
                    if selectedYear == 0 {
                        Image(systemName: "checkmark").foregroundStyle(.blue)
                    }
                }
            }
            ForEach((1940...maxYear).reversed(), id: \.self) { year in
                Button {
                    onSelect(year)
                    dismiss()
                } label: {
                    HStack {
                        Text(String(year))
                        Spacer()
                        if selectedYear == year {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Birth Year")
    }
}

struct HomeView: View {
    @EnvironmentObject var viewModel: ScoreViewModel
    @Environment(\.openURL) private var openURL
    @State private var showMatchView = false
    @State private var showInstructions = false
    @State private var showSettings = false
    @State private var showEndMatchConfirmation = false
    @State private var showStartMatchOptions = false
    @State private var pendingMatchStart = false
    @State private var showTrickyRules = false
    @State private var showTrickyPadelRules = false
    @State private var showHistory = false
    @State private var announcementTestResult: (message: String, success: Bool)?
    @State private var hasPastMatches = false
    private let contactMailtoURL = URL(string: "mailto:mail@ehsanrahman.com?subject=DeuceMate%20Feedback")

    var matchInProgress: Bool {
        viewModel.sets.contains(where: { $0.gamesMe > 0 || $0.gamesOpponent > 0 }) ||
        viewModel.currentPointsMe > 0 || viewModel.currentPointsOpponent > 0 ||
        viewModel.currentServer != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if matchInProgress {
                        showMatchView = true
                    } else {
                        showStartMatchOptions = true
                    }
                } label: {
                    Label(
                        matchInProgress ? "Resume Match" : "Start Match",
                        systemImage: matchInProgress ? "arrow.clockwise" : "play.fill"
                    )
                }
                .font(.headline)
                .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonPrimary))

                // What this match will actually record — stated before the first
                // point, because none of it can be added afterwards. Taps to Settings.
                LiveTrackingStatusStrip(
                    viewModel: viewModel,
                    workoutManager: viewModel.workoutManager
                ) {
                    showSettings = true
                }

                if matchInProgress {
                    Button {
                        showEndMatchConfirmation = true
                    } label: {
                        Label("End Match", systemImage: "stop.fill")
                    }
                    .font(.headline)
                    .buttonStyle(HomeButtonStyle(background: ButtonGradients.end))
                }

                if hasPastMatches {
                    Button {
                        showHistory = true
                    } label: {
                        Label("Past Matches", systemImage: "list.bullet.rectangle")
                    }
                    .font(.headline)
                    .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonServerOpponent))
                }

                HStack(spacing: 8) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                            .labelStyle(.iconOnly)
                    }
                    .font(.subheadline)
                    .buttonStyle(HomeButtonStyle(background: ButtonGradients.guide))

                    Button {
                        showInstructions = true
                    } label: {
                        Label("Guide", systemImage: "book.fill")
                            .labelStyle(.iconOnly)
                    }
                    .font(.subheadline)
                    .buttonStyle(HomeButtonStyle(background: ButtonGradients.guide))
                }

            }
            .padding()
        }
        .sheet(isPresented: $showMatchView) {
            RootModal()
        }
        .sheet(isPresented: $showStartMatchOptions, onDismiss: {
            if pendingMatchStart {
                pendingMatchStart = false
                showMatchView = true
            }
        }) {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        Text("Match Format")
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Button {
                            viewModel.matchFormat = .standard
                            pendingMatchStart = true
                            showStartMatchOptions = false
                        } label: {
                            MatchFormatLabel(
                                title: "Best of 3 Sets (Club / League)",
                                details: "3 sets · Final set: Super Tiebreak to 10"
                            )
                        }
                        .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonPrimary))
                        Button {
                            viewModel.matchFormat = .bestOf3FullFinalSet
                            pendingMatchStart = true
                            showStartMatchOptions = false
                        } label: {
                            MatchFormatLabel(
                                title: "Best of 3 Sets (ATP)",
                                details: "3 sets · Final set: Full set, tiebreak to 7"
                            )
                        }
                        .buttonStyle(HomeButtonStyle(background: viewModel.selectedTheme.colors.buttonPrimary))
                        Button {
                            viewModel.matchFormat = .quick4Games
                            pendingMatchStart = true
                            showStartMatchOptions = false
                        } label: {
                            MatchFormatLabel(
                                title: "Quick 4 Games",
                                details: "First to 3 games · Sudden death point at 2-2"
                            )
                        }
                        .buttonStyle(HomeButtonStyle(background: ButtonGradients.support))
                        Button {
                            viewModel.matchFormat = .superTiebreak
                            pendingMatchStart = true
                            showStartMatchOptions = false
                        } label: {
                            MatchFormatLabel(
                                title: "Super Tiebreak",
                                details: "1 set · Single tiebreak to 10 pts"
                            )
                        }
                        .buttonStyle(HomeButtonStyle(background: ButtonGradients.support))
                        Button {
                            viewModel.matchFormat = .perpetualSuperTiebreak
                            pendingMatchStart = true
                            showStartMatchOptions = false
                        } label: {
                            MatchFormatLabel(
                                title: "Perpetual Tiebreak",
                                details: "Continuous tiebreak until stopping"
                            )
                        }
                        .buttonStyle(HomeButtonStyle(background: ButtonGradients.support))
                        Button {
                            viewModel.matchFormat = .perpetualPoints
                            pendingMatchStart = true
                            showStartMatchOptions = false
                        } label: {
                            MatchFormatLabel(
                                title: "Perpetual Points",
                                details: "Just count points · server alternates every point · no stats or changeovers"
                            )
                        }
                        .buttonStyle(HomeButtonStyle(background: ButtonGradients.support))
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    // Mirrors the start-screen strip, with room for the detail —
                    // including Health, which has no in-app toggle and can only
                    // be granted from the iPhone.
                    Text("What This Match Records")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    LiveTrackingStatusRows(
                        viewModel: viewModel,
                        workoutManager: viewModel.workoutManager
                    )
                    Divider().padding(.vertical, 4)
                    Toggle(isOn: $viewModel.statsTrackingEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Track point outcome")
                            Text(SettingsCopy.trackPointOutcome.text)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(matchInProgress)
                    Toggle(isOn: $viewModel.checkChangeover) {
                        VStack(alignment: .leading, spacing: 2) {
                            (Text("Changeover Compass")
                             + Text(" · Experimental").font(.caption2).foregroundColor(.secondary))
                            Text(SettingsCopy.changeoverCompass.text)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    Toggle(isOn: Binding(
                        get: { viewModel.phoneAnnouncementsEnabled },
                        set: { viewModel.applyIncomingAnnouncements($0, pushToPhone: true) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Announce scores aloud on iPhone")
                            Text(SettingsCopy.announceScores.text)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    if viewModel.phoneAnnouncementsEnabled {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your name")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("e.g. Federer", text: $viewModel.playerName)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .textFieldStyle(.plain)
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button {
                            announcementTestResult = nil
                            let trimmed = viewModel.playerName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let phrase = trimmed.isEmpty ? "Hello" : "Hello \(trimmed)"
                            WatchMatchSyncService.shared.sendAnnouncement(phrase) { success in
                                DispatchQueue.main.async {
                                    announcementTestResult = success
                                        ? (message: "iPhone reached ✓", success: true)
                                        : (message: "iPhone not reachable", success: false)
                                }
                            }
                        } label: {
                            Text("Test iPhone speaker")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        if let result = announcementTestResult {
                            Text(result.message)
                                .font(.footnote)
                                .foregroundStyle(result.success ? .green : .red)
                        }
                    }
                    Toggle(isOn: Binding(
                        get: { viewModel.iPhoneInputEnabled },
                        set: { viewModel.applyIncomingIPhoneInput($0, pushToPhone: true) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iPhone Input")
                            Text(SettingsCopy.iPhoneInput.text)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Appearance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(SettingsCopy.appearanceTheme.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(AppTheme.allCases) { t in
                            Button {
                                viewModel.selectedTheme = t
                            } label: {
                                HStack(spacing: 6) {
                                    HStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(t.colors.me)
                                            .frame(width: 9, height: 9)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(t.colors.opponent)
                                            .frame(width: 9, height: 9)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(t.colors.server)
                                            .frame(width: 9, height: 9)
                                    }
                                    Text(t.displayName)
                                        .font(.footnote)
                                        .foregroundStyle(viewModel.selectedTheme == t ? .primary : .secondary)
                                    Spacer()
                                    if viewModel.selectedTheme == t {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(viewModel.selectedTheme == t ? .isSelected : [])
                        }
                    }
                    Divider().padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pulse Coach")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)

                        HStack {
                            Text(viewModel.userBirthYear == 0 ? "Max HR (default)" : "Max HR (resolved)")
                            Spacer()
                            Text("\(viewModel.resolvedMaxHR) bpm")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption2)
                        .opacity(viewModel.isHROverrideActive ? 0.45 : 1)

                        if viewModel.userBirthYear == 0 && !viewModel.isHROverrideActive {
                            Text(SettingsCopy.defaultMaxHRNote)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        NavigationLink {
                            BirthYearPickerView(
                                selectedYear: viewModel.userBirthYear,
                                onSelect: { selected in
                                    guard selected != viewModel.userBirthYear else { return }
                                    viewModel.userBirthYear = selected
                                    WatchMatchSyncService.shared.pushSharedUserBirthYear(selected)
                                }
                            )
                        } label: {
                            HStack {
                                Text("Birth Year")
                                Spacer()
                                Text(viewModel.userBirthYear == 0 ? "Skip" : String(viewModel.userBirthYear))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.footnote)
                        }
                        .disabled(viewModel.isHROverrideActive)
                        .opacity(viewModel.isHROverrideActive ? 0.45 : 1)

                        Text(SettingsCopy.birthYear.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .opacity(viewModel.isHROverrideActive ? 0.45 : 1)

                        Toggle(isOn: Binding(
                            get: { viewModel.isHROverrideActive },
                            set: { enabled in
                                viewModel.userMaxHROverride = enabled ? HRZone.defaultOverrideBPM : 0
                                WatchMatchSyncService.shared.pushSharedUserMaxHROverride(
                                    viewModel.userMaxHROverride
                                )
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Override Max HR")
                                Text(SettingsCopy.overrideMaxHR.text)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        if viewModel.isHROverrideActive {
                            Stepper(value: Binding(
                                get: { viewModel.userMaxHROverride },
                                set: { newValue in
                                    guard newValue != viewModel.userMaxHROverride else { return }
                                    viewModel.userMaxHROverride = newValue
                                    WatchMatchSyncService.shared.pushSharedUserMaxHROverride(newValue)
                                }
                            ), in: 120...220, step: 1) {
                                HStack {
                                    Text("Override")
                                    Spacer()
                                    Text("\(viewModel.userMaxHROverride) bpm")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.footnote)
                            }
                        }

                        Text("When Override is on, birth year and resolved value are replaced by your manual entry. Heart-rate data syncs with your iPhone. DeuceMate's automatic iCloud Drive archive excludes it, but an iPhone export may include it.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .padding()
            }
            } // NavigationStack
        }
        .sheet(isPresented: $showInstructions) {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Text("Swipe to Score:")
                            }
                            HStack(alignment: .top) {
                                Image(systemName: "hand.point.up.fill")
                                Text("Swipe **up** to gain a point.")
                            }
                            HStack(alignment: .top) {
                                Image(systemName: "hand.point.down.fill")
                                Text("Swipe **down** to give opponent a point.")
                            }
                            HStack(alignment: .top) {
                                Image(systemName: "hand.point.left.fill")
                                Text("Swipe **left** to undo.")
                            }
                            HStack(alignment: .top) {
                                Image(systemName: "hand.point.right.fill")
                                Text("Swipe **right** for score stats — requires **Track point outcome** enabled before the match.")
                            }
                            HStack(alignment: .top) {
                                Image(systemName: "hand.tap.fill")
                                Text("**Double-tap** the score to mark a 2nd serve (yellow **2** badge on the server).")
                            }
                        }
                        .font(.footnote)

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {

                            HStack(alignment: .top) {
                                Text("Match Indicators:")
                            }
                            HStack(alignment: .top) {
                                Text("🎾 Current server & which side to play.")
                            }
                            HStack(alignment: .top) {
                                Text("🟡 **2** — server is on a 2nd serve.")
                            }
                            HStack(alignment: .top) {
                                Text("🧭 Compass arrow points to your starting end at changeovers (when Changeover Compass is on).")
                            }
                            HStack {
                                Text("🔁 🎾 Balls swap ends")
                            }
                            HStack {
                                Text("🔁 👥 Players swap ends")
                            }
                            HStack {
                                Text("🔁 🎾 👥 Balls and players swap ends")
                            }
                        }
                        .font(.footnote)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                showTrickyRules.toggle()
                            } label: {
                                HStack {
                                    Text("**Tricky** Tennis Rules")
                                    Spacer()
                                    Image(systemName: showTrickyRules ? "chevron.up" : "chevron.down")
                                }
                            }

                            if showTrickyRules {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("**Sets**: Switch after 1 game in a set, then every odd game. If a set ends on odd total (6-3, 7-6), switch before next set.")
                                    Text("**Tiebreaks**: Player who would serve next starts with one point, alternate every two points, switch ends every six points. Receiver at start of tiebreak serves next set.")
                                    Text("**Serves**: Foot faults occur when stepping on the imaginary center line extension. Receiver can stand inside service box but must let ball bounce. ")
                                }
                                .padding(.top, 4)
                            }
                        }
                        .font(.footnote)
                        
                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                showTrickyPadelRules.toggle()
                            } label: {
                                HStack {
                                    Text("**Tricky** Padel Rules")
                                    Spacer()
                                    Image(systemName: showTrickyPadelRules ? "chevron.up" : "chevron.down")
                                }
                            }

                            if showTrickyPadelRules {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("**Serve**: Must be underhand, below waist, and after one bounce. Serve can hit the back glass after the bounce, but may not hit the side glass first.")
                                    Text("**Return**: Receiver can let the ball bounce, hit the back wall, then play it back. Volleying before the bounce is allowed (except return of serve).")
                                    Text("**Double wall**: A ball that hits the back wall then side wall (or side then back) is still in play after the bounce; play it if it doesn’t hit the fence first.")
                                }
                                .padding(.top, 4)
                            }
                        }
                        .font(.footnote)
                        
                        Divider()

                        if let contactMailtoURL {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Questions or issues?")
                                Button("Email me here") {
                                    openURL(contactMailtoURL)
                                }
                                .font(.headline)
                                .buttonStyle(HomeButtonStyle(background: ButtonGradients.support))
                            }
                            .font(.footnote)
                        }
                }
                .padding()
            }
        }
        .alert("Finish? 🏁", isPresented: $showEndMatchConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End Match", role: .destructive) {
                viewModel.resetMatch()
                hasPastMatches = !StatsStore.shared.loadHistory().isEmpty
            }
        }
        .sheet(isPresented: $showHistory, onDismiss: {
            hasPastMatches = !StatsStore.shared.loadHistory().isEmpty
        }) {
            MatchHistoryView()
                .environmentObject(viewModel)
        }
        .onChange(of: viewModel.shouldOpenMatchView) { open in
            guard open else { return }
            viewModel.shouldOpenMatchView = false
            showHistory = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                showMatchView = true
            }
        }
        .onAppear {
            hasPastMatches = !StatsStore.shared.loadHistory().isEmpty
            // Health access can be revoked from the iPhone while the app is
            // backgrounded, so re-read it whenever the start screen appears.
            viewModel.workoutManager.refreshHealthAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchMatchHistoryDidChange)) { _ in
            hasPastMatches = !StatsStore.shared.loadHistory().isEmpty
        }
    }

}

private struct MatchFormatLabel: View {
    let title: String
    let details: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(details)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct HomeButtonStyle: ButtonStyle {
    var background: LinearGradient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(background.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
