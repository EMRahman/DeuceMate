// AICoachSheet.swift — One-tap launch surface for the AI coaching prompt.
// Lists installed AI apps (ChatGPT, Claude, Gemini, …) so users can jump
// straight in instead of going through the system share sheet.
import SwiftUI
import DeuceMateCore

struct AICoachSheet: View {
    enum Perspective: String, CaseIterable, Identifiable {
        case me
        case opponent
        var id: String { rawValue }
        var label: String { self == .me ? "My Stats" : "Opponent's" }
    }

    let mePrompt: String
    let opponentPrompt: String
    let hasOpponentPrompt: Bool
    let filenameMe: String
    let filenameOpponent: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var perspective: Perspective = .me
    @State private var installed: [AICoachApp] = []
    @State private var toast: String?
    @State private var toastWorkItem: DispatchWorkItem?

    private var activePrompt: String {
        perspective == .me ? mePrompt : opponentPrompt
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
        }
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
