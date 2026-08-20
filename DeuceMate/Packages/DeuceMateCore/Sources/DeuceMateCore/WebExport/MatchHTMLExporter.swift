// MatchHTMLExporter.swift — assembles ONE self-contained, offline, interactive
// HTML document for a single match. No external assets, no CDN, no network: the
// match data (a `MatchWebViewModel`) is embedded inline and the viewer
// (`MatchWebTemplate`) renders it with hand-written, dependency-free SVG/JS.
//
// Pure and platform-neutral so it is directly unit-testable in the Core package
// with no app/bundle dependency.
import Foundation
import os

private let exportLogger = Logger(subsystem: "com.deucemate.export", category: "MatchHTMLExporter")

public enum MatchHTMLExporter {

    /// The complete self-contained HTML page for `record`. Pass the pre-generated
    /// AI coaching prompts (`MatchExporter.aiPromptExport`) to surface the AI
    /// Coach card; omit them for a prompt-free page.
    public nonisolated static func html(for record: MatchRecord, maxHR: Int = 190,
                                        aiPromptMe: String? = nil,
                                        aiPromptOpponent: String? = nil) -> String {
        let vm = MatchWebViewModel.make(from: record, maxHR: maxHR,
                                        aiPromptMe: aiPromptMe, aiPromptOpponent: aiPromptOpponent)
        let json = encode(vm)
        return MatchWebTemplate.page(jsonLiteral: json, fallbackHTML: staticFallback(vm))
    }

    /// Encode the view model to a JSON literal safe to inline inside a `<script>`.
    /// Keys are sorted for stable, diffable output.
    static func encode(_ vm: MatchWebViewModel) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(vm)
        } catch {
            // `{}` keeps the page valid and the no-JavaScript static fallback
            // still renders the match, so this stays non-throwing — but a
            // silently interactive-less export must be diagnosable.
            exportLogger.error("Failed to encode match web view model; exporting static fallback only: \(error.localizedDescription, privacy: .public)")
            data = Data("{}".utf8)
        }
        let raw = String(decoding: data, as: UTF8.self)
        return scriptSafe(raw)
    }

    // The static (no-JavaScript) `#root` fallback lives in
    // `MatchWebStaticFallback.swift` (`staticFallback`, `staticChartSVG`, `esc`).

    /// Neutralise sequences that would prematurely close the host `<script>` or
    /// open an HTML comment, and escape the JS line separators. The result is
    /// still valid JavaScript (an object literal) and parses identically.
    static func scriptSafe(_ json: String) -> String {
        var s = json
        s = s.replacingOccurrences(of: "</", with: "<\\/")
        s = s.replacingOccurrences(of: "<!--", with: "<\\!--")
        s = s.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        s = s.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return s
    }
}
