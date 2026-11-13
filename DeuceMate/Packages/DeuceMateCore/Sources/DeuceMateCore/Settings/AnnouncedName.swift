// AnnouncedName.swift — the name spoken for the recorder in iPhone score
// announcements ("Advantage John", "Game John").
//
// It is a separate synced setting (`MatchSyncKey.announcedName`) from "Your
// name" (`MatchSyncKey.playerName`), which names the recorder in reports and AI
// prompts. An umpire calls a player by one short name, so while the announced
// name is empty it follows the FIRST name of "Your name" — and keeps following
// it if "Your name" later changes. Only a typed value overrides it.
import Foundation

public enum AnnouncedName {
    /// Placeholder shown when there is no "Your name" to derive a default from.
    public static let examplePlaceholder = "e.g. John"

    /// The first word of `fullName`, or nil when it is blank.
    public static func firstName(of fullName: String) -> String? {
        fullName
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)
    }

    /// The name to speak for the recorder: the typed announced name when set,
    /// otherwise the first name of "Your name". Nil when both are blank — the
    /// caller supplies its own fallback ("you").
    public static func resolve(announcedName: String, playerName: String) -> String? {
        let typed = announcedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return firstName(of: playerName)
    }

    /// Placeholder for the empty field: the default it will use (the first name
    /// of "Your name"), or the generic example when there is none.
    public static func placeholder(playerName: String) -> String {
        firstName(of: playerName) ?? examplePlaceholder
    }
}
