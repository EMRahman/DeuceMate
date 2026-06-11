// SettingsView.swift — Sync status, "Sync now" trigger, and About.
import SwiftUI
import UniformTypeIdentifiers
import DeuceMateCore

// MARK: - Theme skin picker

private struct ThemeSkinPicker: View {
    @Binding var selection: AppTheme

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AppTheme.allCases) { theme in
                Button { selection = theme } label: {
                    ThemeSkinCard(theme: theme, isSelected: selection == theme)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(selection == theme ? .isSelected : [])
                .accessibilityLabel(theme.displayName)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ThemeSkinCard: View {
    let theme: AppTheme
    let isSelected: Bool

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(c.me).frame(width: 16, height: 16)
                Circle().fill(c.opponent).frame(width: 16, height: 16)
                Circle().fill(c.server).frame(width: 16, height: 16)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            Text(theme.displayName)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(Color.white.opacity(isSelected ? 1.0 : 0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? c.me : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
    }
}

// MARK: - Manual archive file document

private struct MatchArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ArchiveTransferStatus: Equatable {
    let message: String
    let isSuccess: Bool
}

// MARK: - Settings view

struct SettingsView: View {
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    @EnvironmentObject private var announcementService: LiveAnnouncementService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: PhoneStatsStore = .shared

    // Shared settings
    @AppStorage("selectedTheme") private var themeRawValue: String = AppTheme.default.rawValue
    @AppStorage("iPhoneInputEnabled") private var iPhoneInputEnabled: Bool = false
    @AppStorage("playerName") private var playerName: String = ""
    @AppStorage("userBirthYear") private var userBirthYear: Int = 0
    @AppStorage("userBirthYearFromHealth") private var userBirthYearFromHealth: Bool = false
    @AppStorage("userMaxHROverride") private var userMaxHROverride: Int = 0
    @AppStorage("maxHRComputed") private var maxHRComputed: Int = 0
    @AppStorage("playerNTRP") private var playerNTRP: String = "3.0–3.5"

    // Watch-only settings (phone controls watch)
    @AppStorage("statsTrackingEnabled") private var statsTrackingEnabled: Bool = false
    @AppStorage("checkChangeover") private var checkChangeover: Bool = false

    private enum PingStatus: Equatable {
        case inFlight
        case done(success: Bool, message: String)
    }

    @State private var pingStatus: PingStatus?
    @State private var syncStatus: PingStatus?
    @State private var syncRequestedAt: Date?
    @State private var showSyncDetails = false
    @State private var showArchiveExportDisclosure = false
    @State private var showArchiveExporter = false
    @State private var showArchiveImporter = false
    @State private var showArchiveImportOptions = false
    @State private var showArchiveReplaceConfirmation = false
    @State private var archiveExportDocument = MatchArchiveDocument()
    @State private var pendingImportData: Data?
    @State private var pendingImportPreview: ManualMatchArchiveBackup.ImportPreview?
    @State private var archiveTransferStatus: ArchiveTransferStatus?

    private var selectedTheme: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: themeRawValue) ?? .default },
            set: { themeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        List {
            watchConfigSection
            sharedConfigSection
            pulseCoachSectionView
            aiCoachingSection
            iPhoneOnlySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onChange(of: syncService.lastSyncDate) { newDate in
            guard syncStatus == .inFlight,
                  let requestedAt = syncRequestedAt,
                  let date = newDate,
                  date >= requestedAt else { return }
            syncStatus = .done(success: true, message: "Sync completed ✓")
            syncRequestedAt = nil
        }
        .alert("Export Match Archive", isPresented: $showArchiveExportDisclosure) {
            Button("Export") { prepareManualArchiveExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The JSON file includes your full match archive and may include HealthKit-derived heart rate, steps, distance, and calories when those were recorded.")
        }
        .fileExporter(
            isPresented: $showArchiveExporter,
            document: archiveExportDocument,
            contentType: .json,
            defaultFilename: manualArchiveFilename
        ) { result in
            switch result {
            case .success:
                archiveTransferStatus = ArchiveTransferStatus(
                    message: "Archive exported",
                    isSuccess: true
                )
            case .failure(let error):
                archiveTransferStatus = ArchiveTransferStatus(
                    message: "Export failed: \(error.localizedDescription)",
                    isSuccess: false
                )
            }
        }
        .fileImporter(
            isPresented: $showArchiveImporter,
            allowedContentTypes: [.json]
        ) { result in
            handleManualArchiveImportSelection(result)
        }
        .confirmationDialog(
            "Import Match Archive",
            isPresented: $showArchiveImportOptions,
            titleVisibility: .visible,
            presenting: pendingImportPreview
        ) { _ in
            Button("Merge") { runManualArchiveImport(mode: .merge) }
            Button("Replace Archive", role: .destructive) {
                DispatchQueue.main.async {
                    showArchiveReplaceConfirmation = true
                }
            }
            Button("Cancel", role: .cancel) { clearPendingManualArchiveImport() }
        } message: { preview in
            Text(importPreviewMessage(preview))
        }
        .alert(
            "Replace Match Archive?",
            isPresented: $showArchiveReplaceConfirmation,
            presenting: pendingImportPreview
        ) { _ in
            Button("Replace Archive", role: .destructive) {
                runManualArchiveImport(mode: .replace)
            }
            Button("Cancel", role: .cancel) { clearPendingManualArchiveImport() }
        } message: { preview in
            Text("This will replace \(store.history.count) current matches with \(preview.recordCount) imported matches. Imported health data will be preserved.")
        }
    }

    // MARK: - Apple Watch Configurations

    /// Wraps an @AppStorage Bool binding so that any change is followed by a
    /// bundled pushWatchOnlySettings() call, keeping both watch-only values in sync.
    private func watchBinding(for value: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                syncService.pushWatchOnlySettings(
                    statsTracking: statsTrackingEnabled,
                    changeover: checkChangeover
                )
            }
        )
    }

    private var watchConfigSection: some View {
        Section {
            Toggle(isOn: watchBinding(for: $statsTrackingEnabled)) {
                settingLabel("Track point outcome", .trackPointOutcome)
            }
            Toggle(isOn: watchBinding(for: $checkChangeover)) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text("Changeover Compass")
                     + Text(" · Experimental").font(.caption2).foregroundStyle(.secondary))
                    Text(SettingsCopy.changeoverCompass.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            Text("These settings apply to your Apple Watch. Changes on either device are synced — the last update wins.")
        }
    }

    // MARK: - Shared Configurations

    private var sharedConfigSection: some View {
        Section {
            // Appearance
            ThemeSkinPicker(selection: selectedTheme)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .onChange(of: themeRawValue) { newValue in
                    syncService.sendTheme(newValue)
                }
            Text(SettingsCopy.appearanceTheme.text)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Announce Scores Aloud
            Toggle(isOn: Binding(
                get: { announcementService.isEnabled },
                set: { newValue in
                    announcementService.setEnabled(newValue)
                    syncService.pushSharedAnnouncements(newValue)
                }
            )) {
                settingLabel("Announce scores aloud on iPhone", .announceScores)
            }
            if announcementService.isEnabled {
                TextField("Your name (e.g. Federer)", text: Binding(
                    get: { playerName },
                    set: { newValue in
                        playerName = newValue
                        syncService.pushSharedPlayerName(newValue)
                    }
                ))
                .textContentType(.name)
                .autocorrectionDisabled()
                Button {
                    let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let phrase = trimmed.isEmpty ? "Hello" : "Hello \(trimmed)"
                    announcementService.previewVoice(phrase)
                } label: {
                    Label("Test name on iPhone speaker", systemImage: "speaker.wave.2.fill")
                }
                Text("Keep DeuceMate open on screen during the match — scores are spoken through the iPhone speaker or a connected Bluetooth speaker while the app is in the foreground, and pause if you lock the phone or switch apps. Your name personalises announcements and stays in sync with the Watch app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // iPhone Input — spectator-style swipe scoring on the iPhone.
            Toggle(isOn: Binding(
                get: { iPhoneInputEnabled },
                set: { newValue in
                    iPhoneInputEnabled = newValue
                    syncService.pushIPhoneInputEnabled(newValue)
                }
            )) {
                settingLabel("iPhone Input", .iPhoneInput)
            }
            if iPhoneInputEnabled {
                Text("On the iPhone live scoreboard, swipe up to award yourself a point, down for the opponent, and left to undo — like on the Apple Watch. The watch remains the source of truth.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Shared Configurations")
        } footer: {
            Text("These settings apply to both iPhone and Apple Watch. The last value set on either device wins.")
        }
    }

    // MARK: - AI Coaching

    private static let ntRPOptions: [(label: String, value: String)] = [
        ("Beginner (2.5–3.0)", "2.5–3.0"),
        ("Intermediate (3.0–3.5)", "3.0–3.5"),
        ("Club player (3.5–4.5)", "3.5–4.5"),
    ]

    private var aiCoachingSection: some View {
        Section {
            Picker("Player Level (NTRP)", selection: $playerNTRP) {
                ForEach(Self.ntRPOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        } header: {
            Text("AI Coaching")
        } footer: {
            Text(SettingsCopy.playerLevelNTRP.text)
        }
    }

    // MARK: - iPhone Only

    private var iPhoneOnlySection: some View {
        Group {
            Section {
                LabeledContent("Last Synced") {
                    Text(lastSyncedText)
                        .foregroundStyle(.secondary)
                }
                Button {
                    syncNow()
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(syncService.activationState != "Activated" || syncStatus == .inFlight)

                if let syncStatus {
                    switch syncStatus {
                    case .inFlight:
                        Text("Syncing…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .done(let success, let message):
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(success ? .green : .red)
                    }
                }

                DisclosureGroup(isExpanded: $showSyncDetails) {
                    statusRow("Session", value: syncService.activationState,
                              ok: syncService.activationState == "Activated")
                    statusRow("Watch Paired", value: syncService.isPaired ? "Yes" : "No",
                              ok: syncService.isPaired)
                    statusRow("Watch App Installed", value: syncService.isWatchAppInstalled ? "Yes" : "No",
                              ok: syncService.isWatchAppInstalled)
                    statusRow("Watch Reachable", value: syncService.isWatchReachable ? "Yes" : "No (normal)",
                              ok: syncService.isWatchReachable ? true : nil)
                    statusRow("Pending Transfers", value: "\(syncService.pendingTransferCount)",
                              ok: syncService.pendingTransferCount == 0)
                    Button {
                        pingWatch()
                    } label: {
                        Label("Ping Watch", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(syncService.activationState != "Activated")

                    if let pingStatus {
                        switch pingStatus {
                        case .inFlight:
                            Text("Pinging…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        case .done(let success, let message):
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(success ? .green : .red)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Connection Details")
                        Spacer()
                        Image(systemName: syncHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(syncHealthy ? .green : .orange)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(syncHealthy ? "Connection Details, healthy" : "Connection Details, needs attention")
                }
            } header: {
                Text("Watch Sync")
            } footer: {
                Text("Match data is synced between your iPhone and Apple Watch using Apple's WatchConnectivity framework.")
            }

            Section {
                Button {
                    showArchiveExportDisclosure = true
                } label: {
                    Label("Export Match Archive", systemImage: "square.and.arrow.up")
                }
                Button {
                    showArchiveImporter = true
                } label: {
                    Label("Import Match Archive", systemImage: "square.and.arrow.down")
                }
                if let archiveTransferStatus {
                    Text(archiveTransferStatus.message)
                        .font(.footnote)
                        .foregroundStyle(archiveTransferStatus.isSuccess ? .green : .red)
                }
            } header: {
                Text("Backup & Transfer")
            } footer: {
                Text("Manual archive files are full-fidelity JSON exports. They may include HealthKit-derived heart rate, steps, distance, and calories when those were recorded.")
            }

            Section {
                LabeledContent("Version") {
                    Text(Self.appVersion).foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(Self.appBuild).foregroundStyle(.secondary)
                }
                if let url = Self.privacyPolicyURL {
                    Link(destination: url) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                }
                if let url = Self.supportSiteURL {
                    Link(destination: url) {
                        Label("Support & FAQ", systemImage: "questionmark.circle.fill")
                    }
                }
                if let url = Self.supportEmailURL {
                    Link(destination: url) {
                        Label("Contact Support", systemImage: "envelope.fill")
                    }
                }
            } header: {
                Text("About")
            } footer: {
                Text("Your matches stay on your Apple devices and in your own iCloud — no servers, no analytics, no tracking.")
            }
        }
    }

    // MARK: - Pulse Coach (shared — also applied to Apple Watch)

    private var resolvedMaxHR: Int {
        HRZone.resolveMaxHR(
            historical99thPct: maxHRComputed > 0 ? maxHRComputed : nil,
            manualOverride: userMaxHROverride > 0 ? userMaxHROverride : nil,
            birthYear: userBirthYear > 0 ? userBirthYear : nil
        )
    }

    private var isOverrideActive: Bool { HRZone.isValidOverride(userMaxHROverride) }

    private var pulseCoachSectionView: some View {
        Section {
            Picker("Birth Year", selection: Binding(
                get: { userBirthYear == 0 ? -1 : userBirthYear },
                set: { newValue in
                    let resolved = newValue == -1 ? 0 : newValue
                    guard resolved != userBirthYear || userBirthYearFromHealth else { return }
                    userBirthYear = resolved
                    userBirthYearFromHealth = false
                    syncService.pushPulseCoachSettings(
                        maxHR: resolvedMaxHR,
                        birthYear: userBirthYear,
                        birthYearFromHealth: false,
                        maxHROverride: userMaxHROverride
                    )
                }
            )) {
                Text("Skip").tag(-1)
                ForEach((1940...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .disabled(isOverrideActive)
            .opacity(isOverrideActive ? 0.45 : 1)

            Text(SettingsCopy.birthYear.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(isOverrideActive ? 0.45 : 1)

            if userBirthYearFromHealth, userBirthYear > 0 {
                Label("From Apple Health record", systemImage: "heart.text.square")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(isOverrideActive ? 0.45 : 1)
            }

            LabeledContent("Max HR (resolved)") {
                Text("\(resolvedMaxHR) bpm")
                    .foregroundStyle(.secondary)
            }
            .opacity(isOverrideActive ? 0.45 : 1)

            Toggle(isOn: Binding(
                get: { isOverrideActive },
                set: { enabled in
                    userMaxHROverride = enabled ? HRZone.defaultOverrideBPM : 0
                    syncService.pushPulseCoachSettings(
                        maxHR: resolvedMaxHR,
                        birthYear: userBirthYear,
                        birthYearFromHealth: userBirthYearFromHealth,
                        maxHROverride: userMaxHROverride
                    )
                }
            )) {
                settingLabel("Override Max HR", .overrideMaxHR)
            }

            if isOverrideActive {
                Stepper(value: Binding(
                    get: { userMaxHROverride },
                    set: { newValue in
                        userMaxHROverride = newValue
                        syncService.pushPulseCoachSettings(
                            maxHR: resolvedMaxHR,
                            birthYear: userBirthYear,
                            birthYearFromHealth: userBirthYearFromHealth,
                            maxHROverride: userMaxHROverride
                        )
                    }
                ), in: 120...220, step: 1) {
                    LabeledContent("Override value") {
                        Text("\(userMaxHROverride) bpm")
                            .foregroundStyle(.secondary)
                    }
                }
            }

        } header: {
            Text("Pulse Coach (Shared)")
        } footer: {
            Text("These settings apply to both iPhone and Apple Watch. The last value set on either device wins.\n\nWhen Override Max HR is on, birth year and resolved value are replaced by your manual entry. Heart-rate data stays on your devices. Pulse Coach analyses your heart rate alongside each point to surface zone-by-zone win rate and recovery trends.")
        }
    }


    // MARK: - Helpers

    /// A settings row label: the setting title above its one-line summary,
    /// sourced from the shared `SettingsCopy` catalog so it matches the Watch.
    @ViewBuilder
    private func settingLabel(_ title: String, _ copy: SettingsCopy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(copy.text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusRow(_ label: String, value: String, ok: Bool?) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Text(value)
                    .foregroundStyle(.secondary)
                switch ok {
                case true:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case false:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                case nil:
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Overall link health for the collapsed summary row. Reachability is
    /// excluded — the watch is only reachable while both apps are foregrounded,
    /// so "No" is the normal state and shouldn't flag the section.
    private var syncHealthy: Bool {
        syncService.activationState == "Activated"
            && syncService.isPaired
            && syncService.isWatchAppInstalled
            && syncService.pendingTransferCount == 0
    }

    private var lastSyncedText: String {
        guard let date = syncService.lastSyncDate else { return "Never" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func pingWatch() {
        pingStatus = .inFlight
        syncService.ping { success, message in
            DispatchQueue.main.async {
                self.pingStatus = .done(success: success, message: message)
            }
        }
    }

    private func syncNow() {
        let now = Date()
        syncRequestedAt = now
        syncStatus = .inFlight
        syncService.requestFullHistorySync()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            guard self.syncRequestedAt == now, self.syncStatus == .inFlight else { return }
            self.syncStatus = .done(success: false, message: "No response from watch")
            self.syncRequestedAt = nil
        }
    }

    private var manualArchiveFilename: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return "deucemate_archive_\(formatter.string(from: Date())).json"
    }

    private func prepareManualArchiveExport() {
        archiveTransferStatus = nil
        let store = store
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try store.exportManualArchiveData()
                DispatchQueue.main.async {
                    archiveExportDocument = MatchArchiveDocument(data: data)
                    showArchiveExporter = true
                }
            } catch {
                DispatchQueue.main.async {
                    archiveTransferStatus = ArchiveTransferStatus(
                        message: "Export failed: \(error.localizedDescription)",
                        isSuccess: false
                    )
                }
            }
        }
    }

    private func handleManualArchiveImportSelection(_ result: Result<URL, Error>) {
        archiveTransferStatus = nil
        do {
            let url = try result.get()
            let store = store
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if shouldStopAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let data = try Data(contentsOf: url)
                    let preview = try store.previewManualArchiveImport(data: data)
                    DispatchQueue.main.async {
                        pendingImportPreview = preview
                        pendingImportData = data
                        showArchiveImportOptions = true
                    }
                } catch {
                    DispatchQueue.main.async {
                        archiveTransferStatus = ArchiveTransferStatus(
                            message: "Import failed: \(error.localizedDescription)",
                            isSuccess: false
                        )
                        clearPendingManualArchiveImport()
                    }
                }
            }
        } catch {
            archiveTransferStatus = ArchiveTransferStatus(
                message: "Import failed: \(error.localizedDescription)",
                isSuccess: false
            )
            clearPendingManualArchiveImport()
        }
    }

    private func runManualArchiveImport(mode: ManualMatchArchiveBackup.ImportMode) {
        guard let pendingImportData else {
            archiveTransferStatus = ArchiveTransferStatus(
                message: "Import failed: no archive selected",
                isSuccess: false
            )
            return
        }

        archiveTransferStatus = nil
        let store = store
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let preview = try store.importManualArchive(data: pendingImportData, mode: mode)
                let verb = mode == .merge ? "merged" : "replaced"
                DispatchQueue.main.async {
                    archiveTransferStatus = ArchiveTransferStatus(
                        message: "Archive \(verb): \(preview.recordCount) matches imported",
                        isSuccess: true
                    )
                    clearPendingManualArchiveImport()
                }
            } catch {
                DispatchQueue.main.async {
                    archiveTransferStatus = ArchiveTransferStatus(
                        message: "Import failed: \(error.localizedDescription)",
                        isSuccess: false
                    )
                }
            }
        }
    }

    private func clearPendingManualArchiveImport() {
        pendingImportData = nil
        pendingImportPreview = nil
    }

    private func importPreviewMessage(_ preview: ManualMatchArchiveBackup.ImportPreview) -> String {
        let healthText = preview.includesHealthData
            ? "This archive includes HealthKit-derived heart rate, steps, distance, and calories when recorded."
            : "This archive does not report included health data."
        let choices = "Merge keeps your current matches and adds these, preferring the more complete copy of any duplicate. Replace swaps your iPhone archive for this file — matches still on your watch can sync back."
        return "\(preview.recordCount) matches found. \(choices) \(healthText)"
    }

    // The same public pages the App Store listing points at — keep in lockstep
    // with APP_STORE_METADATA.md (Apple requires both URLs to resolve publicly).
    private static let privacyPolicyURL = URL(string: "https://emrahman.github.io/DeuceMate/privacy.html")
    private static let supportSiteURL = URL(string: "https://emrahman.github.io/DeuceMate/")

    // Static: the bundle version and support address can't change mid-process,
    // so these are computed once rather than on every body evaluation.
    private static let appVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    private static let appBuild: String =
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

    /// mailto: link with the app version in the subject so support emails
    /// arrive pre-triaged.
    private static let supportEmailURL: URL? = {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "mail@ehsanrahman.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "DeuceMate Support (v\(appVersion), build \(appBuild))")
        ]
        return components.url
    }()
}
