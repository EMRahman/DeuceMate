// AICoachSheet.swift — One-tap launch surface for the AI coaching prompt.
// Lists installed AI apps (ChatGPT, Claude, Gemini, …) so users can jump
// straight in instead of going through the system share sheet.
import SwiftUI
import DeuceMateCore

/// Everything the prompt closure reads from its parent. The sheet caches the
/// built prompt in state, so it must regenerate when ANY of these change - a
/// Watch checkpoint, match completion or health backfill can arrive while the
/// sheet is open and would otherwise leave Copy/Share/Launch sending a stale
/// score. Equality is by value, so an unchanged re-render never rebuilds.
nonisolated struct AICoachSourceIdentity: Equatable {
    let record: MatchRecord
    let maxHR: Int
    let playerNTRP: String
    let note: String?
    let headToHead: HeadToHeadRecord?
}

struct AICoachSheet: View {
    enum Perspective: String, CaseIterable, Identifiable {
        case me
        case opponent
        var id: String { rawValue }
        var label: String { self == .me ? "My Stats" : "Opponent's" }
    }

    /// Builds the prompt for a perspective with the sheet's own toggles. Pure
    /// and synchronous: the sheet rebuilds whenever a toggle changes, so a
    /// copied or shared prompt always matches what the toggles show.
    let buildPrompt: (_ focal: Player, _ includeNames: Bool, _ includeNotes: Bool) -> String
    let hasOpponentPrompt: Bool
    let filenameMe: String
    let filenameOpponent: String
    /// Whether anyone is tagged on this match (names toggle is shown only then).
    let hasTaggedPeople: Bool
    /// The stored private note, if any (the notes toggle is shown only then).
    let noteText: String?
    /// Refresh identity: the prompt is rebuilt when this changes (see type doc).
    let sourceIdentity: AICoachSourceIdentity

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var perspective: Perspective = .me
    @State private var installed: [AICoachApp] = []
    @State private var toast: String?
    @State private var toastWorkItem: DispatchWorkItem?
    /// Both default OFF every time the sheet opens: names and notes are
    /// per-hand-off opt-ins (MATCH_TAGS_PLAN.md §7.3), never remembered.
    @State private var includeNames = false
    @State private var includeNotes = false
    @State private var showNotesReview = false
    @State private var activePrompt = ""

    private var focal: Player { perspective == .me ? .me : .opponent }

    private func refreshPrompt() {
        activePrompt = buildPrompt(focal, includeNames, includeNotes && noteText != nil)
    }

    private var activeFilename: String {
        perspective == .me ? filenameMe : filenameOpponent
    }

    private var anyAppPrefills: Bool {
        installed.contains { $0.supportsPromptParam }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(theme.colors.me)
                            Text("Get AI Coaching Tips")
                                .font(.headline)
                        }
                        Text("Send your match stats to an AI for personalised coaching feedback.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if hasOpponentPrompt {
                    Section {
                        Picker("Perspective", selection: $perspective) {
                            ForEach(Perspective.allCases) { p in
                                Text(p.label).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(perspective == .me
                             ? "Coaching tips for your own performance."
                             : "Generate a prompt to share with your opponent — coaching for their side of the match.")
                    }
                }

                if hasTaggedPeople || noteText != nil {
                    promptContentsSection
                }

                if installed.isEmpty {
                    Section("Open in AI App") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No supported AI apps detected on this iPhone.")
                                .font(.subheadline)
                            Text("Install ChatGPT, Claude, Gemini, Perplexity, Copilot, Poe, or Grok and they’ll show up here for one-tap access.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section {
                        ForEach(installed) { app in
                            Button {
                                launch(app)
                            } label: {
                                appRow(app)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Open in AI App")
                    } footer: {
                        Text(anyAppPrefills
                             ? "Copies the prompt to your clipboard and opens the app — paste it into a new chat. An Auto-fills badge means the prompt is pre-loaded for you."
                             : "Copies the prompt to your clipboard and opens the app — paste it into a new chat.")
                    }
                }

                Section {
                    Button {
                        AICoachLauncher.copyToClipboard(activePrompt)
                        showToast("Prompt copied to clipboard")
                    } label: {
                        Label("Copy Prompt to Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .accessibilityIdentifier("copy-prompt-to-clipboard")

                    ShareLink(
                        item: activePrompt,
                        subject: Text(perspective == .me
                                      ? "Tennis Match — AI Coaching Prompt"
                                      : "Tennis Match — Opponent AI Coaching Prompt"),
                        message: Text("Paste into your favourite AI tool for coaching tips."),
                        preview: SharePreview(activeFilename, image: Image(systemName: "figure.tennis"))
                    ) {
                        Label("More Share Options…", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Other")
                } footer: {
                    Text("Use any of these if your preferred AI app isn’t listed above.")
                }
            }
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: toast)
        }
        .onAppear {
            installed = AICoachLauncher.installedApps()
            refreshPrompt()
        }
        .onChange(of: perspective) { _, _ in refreshPrompt() }
        .onChange(of: includeNames) { _, _ in refreshPrompt() }
        .onChange(of: includeNotes) { _, _ in refreshPrompt() }
        // Toggles and perspective are @State, so they survive this refresh.
        .onChange(of: sourceIdentity) { _, _ in refreshPrompt() }
        .sheet(isPresented: $showNotesReview) {
            if let noteText {
                NotesExportReviewSheet(
                    noteText: noteText,
                    includeNames: includeNames,
                    destination: "the AI prompt",
                    onConfirm: {
                        includeNotes = true
                        showNotesReview = false
                    },
                    onCancel: { showNotesReview = false }
                )
            }
        }
    }

    // MARK: - Prompt contents (names / private note)

    @ViewBuilder
    private var promptContentsSection: some View {
        Section {
            if hasTaggedPeople {
                Toggle("Include player names", isOn: $includeNames)
                    .accessibilityIdentifier("ai-include-names")
            }
            if noteText != nil {
                Toggle("Include private note", isOn: Binding(
                    get: { includeNotes },
                    set: { wantsOn in
                        // Turning ON goes through the review step; OFF is immediate.
                        if wantsOn { showNotesReview = true } else { includeNotes = false }
                    }
                ))
                .accessibilityIdentifier("ai-include-notes")
            }
            NavigationLink {
                promptPreview
            } label: {
                Label("Preview Prompt", systemImage: "doc.text.magnifyingglass")
            }
            .accessibilityIdentifier("ai-preview-prompt")
        } header: {
            Text("Prompt Contents")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if hasTaggedPeople {
                    Text(MatchExportDisclosure.namesCaption(isOn: includeNames, forAI: true))
                }
                if noteText != nil {
                    Text(includeNotes
                         ? "Your private note is quoted in the prompt as background context."
                         : "Your private note is not included.")
                }
                if includeNotes && !includeNames {
                    Text(MatchExportDisclosure.namesOffNotesWarning)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("ai-names-off-notes-warning")
                }
            }
        }
    }

    private var promptPreview: some View {
        ScrollView {
            Text(activePrompt)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityIdentifier("ai-prompt-text")
        }
        .navigationTitle("Prompt")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func appRow(_ app: AICoachApp) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(app.tint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: app.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(app.tint)
            }
            Text("Open in \(app.name)")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            if app.supportsPromptParam {
                Text("Auto-fills")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(app.tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(app.tint)
            }
            Spacer()
            Image(systemName: "arrow.up.forward.app")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func launch(_ app: AICoachApp) {
        AICoachLauncher.launch(app, with: activePrompt)
        showToast("Prompt copied — opening \(app.name)…")
    }

    private func showToast(_ message: String) {
        toast = message
        toastWorkItem?.cancel()
        let work = DispatchWorkItem {
            withAnimation { toast = nil }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}
