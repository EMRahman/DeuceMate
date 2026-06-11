// AICoachLauncher.swift — Detects installed third-party AI apps and routes a
// generated coaching prompt to them with a single tap. Falls back to the
// system clipboard + share sheet when no supported app is installed.
import SwiftUI
import UIKit

/// One of the third-party AI chat apps we can hand a coaching prompt to.
/// `scheme` is used both for `canOpenURL` detection (the bare URL form
/// `<scheme>://`) and for the launch URL. `launchURL` returns the actual
/// URL we open — most apps cold-launch on the bare scheme; a few accept
/// query-style search params we can pre-fill.
struct AICoachApp: Identifiable, Hashable {
    let id: String
    let name: String
    let scheme: String
    let systemImage: String
    let tint: Color
    /// If true the app accepts a `?q=` style prompt in the URL; otherwise
    /// we just open the app and the user pastes from the clipboard.
    let supportsPromptParam: Bool

    static let all: [AICoachApp] = [
        AICoachApp(id: "chatgpt",
                   name: "ChatGPT",
                   scheme: "chatgpt",
                   systemImage: "bubble.left.and.text.bubble.right.fill",
                   tint: Color(red: 0.10, green: 0.64, blue: 0.50),
                   supportsPromptParam: false),
        AICoachApp(id: "claude",
                   name: "Claude",
                   scheme: "claude",
                   systemImage: "sparkle",
                   tint: Color(red: 0.85, green: 0.45, blue: 0.18),
                   supportsPromptParam: false),
        AICoachApp(id: "gemini",
                   name: "Gemini",
                   scheme: "googlegemini",
                   systemImage: "diamond.fill",
                   tint: Color(red: 0.26, green: 0.52, blue: 0.96),
                   supportsPromptParam: false),
        AICoachApp(id: "perplexity",
                   name: "Perplexity",
                   scheme: "perplexity",
                   systemImage: "magnifyingglass.circle.fill",
                   tint: Color(red: 0.16, green: 0.54, blue: 0.62),
                   supportsPromptParam: true),
        AICoachApp(id: "copilot",
                   name: "Copilot",
                   scheme: "ms-copilot",
                   systemImage: "cpu.fill",
                   tint: Color(red: 0.18, green: 0.42, blue: 0.84),
                   supportsPromptParam: false),
        AICoachApp(id: "poe",
                   name: "Poe",
                   scheme: "poe",
                   systemImage: "ellipsis.bubble.fill",
                   tint: Color(red: 0.50, green: 0.32, blue: 0.92),
                   supportsPromptParam: false),
        AICoachApp(id: "grok",
                   name: "Grok",
                   scheme: "grok",
                   systemImage: "bolt.fill",
                   tint: Color(red: 0.20, green: 0.20, blue: 0.22),
                   supportsPromptParam: false),
    ]

    var probeURL: URL? { URL(string: "\(scheme)://") }
}

enum AICoachLauncher {
    /// Returns the subset of `AICoachApp.all` that are currently installed
    /// on this device. Relies on `LSApplicationQueriesSchemes` containing
    /// each scheme — otherwise `canOpenURL` always returns false.
    @MainActor
    static func installedApps() -> [AICoachApp] {
        AICoachApp.all.filter { app in
            guard let url = app.probeURL else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
    }

    /// Copies the prompt to the system clipboard, then opens the chosen
    /// app. Apps that accept a search query get the prompt pre-filled,
    /// truncated to a safe URL length; the full prompt is always on the
    /// clipboard so the user can paste if the pre-fill is too short.
    @MainActor
    static func launch(_ app: AICoachApp, with prompt: String) {
        UIPasteboard.general.string = prompt

        let url: URL
        if app.supportsPromptParam,
           let promptURL = promptURL(for: app, prompt: prompt) {
            url = promptURL
        } else if let bare = app.probeURL {
            url = bare
        } else {
            return
        }
        UIApplication.shared.open(url)
    }

    /// Copies the prompt to the clipboard without opening anything.
    @MainActor
    static func copyToClipboard(_ prompt: String) {
        UIPasteboard.general.string = prompt
    }

    private static func promptURL(for app: AICoachApp, prompt: String) -> URL? {
        // URL-bar limits vary by app; keep it well under 2 KB to be safe.
        let trimmed = String(prompt.prefix(1500))
        switch app.id {
        case "perplexity":
            var components = URLComponents()
            components.scheme = "perplexity"
            components.host = "search"
            components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
            return components.url
        default:
            return app.probeURL
        }
    }
}
