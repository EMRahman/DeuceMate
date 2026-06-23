// MatchWebViewModel+AICoach.swift — assembles the AI Coach block the viewer
// renders, mirroring the iOS `AICoachSheet`: the explanatory copy, the (already
// generated) coaching prompt(s), and the list of AI apps to launch into.
//
// The prompt TEXT is generated upstream by `MatchExporter.aiPromptExport` and
// passed in — this builder only attaches the static app list + copy, so the
// produced page works identically to the iOS sheet. Launch URLs are the AI
// services' web entry points (opened on a user click, never fetched on load);
// the page itself still loads zero external resources.
import Foundation

extension MatchWebViewModel {

    /// `nil` when no prompt is supplied (a bare `html(for:)` with no AI text),
    /// so the viewer simply omits the AI Coach card.
    static func buildAICoach(mePrompt: String?, opponentPrompt: String?) -> AICoach? {
        guard let me = mePrompt, !me.isEmpty else { return nil }
        let opp = (opponentPrompt?.isEmpty == false) ? opponentPrompt : nil
        return AICoach(
            title: "Get AI Coaching Tips",
            intro: "Send your match stats to an AI for personalised coaching feedback.",
            mePrompt: me,
            opponentPrompt: opp,
            apps: aiApps
        )
    }

    /// Web launch targets for the same AI apps the iOS sheet offers, in the same
    /// order. Colours mirror `AICoachLauncher`'s tints. Only Perplexity accepts a
    /// `?q=` pre-fill (matching iOS); the rest open and the user pastes.
    static let aiApps: [AICoach.App] = [
        .init(name: "ChatGPT",    url: "https://chatgpt.com/",            colorHex: "#1AA380", supportsPromptParam: false),
        .init(name: "Claude",     url: "https://claude.ai/new",           colorHex: "#D9732E", supportsPromptParam: false),
        .init(name: "Gemini",     url: "https://gemini.google.com/app",   colorHex: "#4285F5", supportsPromptParam: false),
        .init(name: "Perplexity", url: "https://www.perplexity.ai/search", colorHex: "#298A9E", supportsPromptParam: true),
        .init(name: "Copilot",    url: "https://copilot.microsoft.com/",  colorHex: "#2E6BD6", supportsPromptParam: false),
        .init(name: "Poe",        url: "https://poe.com/",                colorHex: "#8052EB", supportsPromptParam: false),
        .init(name: "Grok",       url: "https://grok.com/",               colorHex: "#333338", supportsPromptParam: false)
    ]
}
