// ExportFilenames.swift — filenames for shared match exports.
//
// Deliberately takes only the match START TIME: a filename shows up in Files,
// AirDrop previews, iCloud Drive listings and email attachments, outside the
// report's own context, so it must never carry a player's name, a competition
// or any other tag (MATCH_TAGS_PLAN.md §7.3 / S4). With no tag parameter there
// is no way to leak one.
import Foundation

nonisolated enum ExportFilenames {

    /// "deuce_mate_2026-11-01_ai_prompt_opponent.txt" - date plus a fixed suffix.
    static func text(startTime: Date, suffix: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return "deuce_mate_\(f.string(from: startTime))\(suffix).txt"
    }

    /// "deuce_mate_2026-11-01_1530[_opponent].html". Includes the start time
    /// so same-day matches don't collide in the temporary directory; the POSIX
    /// locale keeps the format deterministic.
    static func html(startTime: Date, opponentPerspective: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return "deuce_mate_\(f.string(from: startTime))\(opponentPerspective ? "_opponent" : "").html"
    }
}
