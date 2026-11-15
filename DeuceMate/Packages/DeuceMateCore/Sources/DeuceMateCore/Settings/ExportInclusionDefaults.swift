// ExportInclusionDefaults.swift — what a shared report, AI Coach prompt or
// game plan pack includes before the player changes anything, and which of
// those choices the iPhone remembers.
//
// - Player names start ON and the player's choice is remembered: someone who
//   turns names off once shouldn't have to do it again for every hand-off.
//   One choice covers the share menu, AI Coach and Prepare Game Plan.
// - Playing style notes (Prepare Game Plan only) start ON and are remembered.
//   They exist to brief the player's own AI for a match against that player.
// - Private match notes start OFF on every export, AI prompt and game plan and
//   are never remembered. Including them always goes through a review of the
//   exact text, because they may hold personal or health information about
//   the player or someone else.
//
// iPhone-local only (see CLAUDE.md §0): these keys never sync to the Watch and
// have no `MatchSyncKey`. The raw strings are pinned by
// `ExportInclusionDefaultsTests`; renaming one silently resets the player's
// remembered choice.
import Foundation

public enum ExportInclusionDefaults {
    /// `UserDefaults` key for the remembered "Include player names" choice.
    public static let includePlayerNamesKey = "exportIncludePlayerNames"
    /// Player names are included until the player turns them off.
    public static let includePlayerNames = true

    /// `UserDefaults` key for Prepare Game Plan's remembered "Playing style notes" choice.
    public static let includePlayingNotesKey = "gamePlanIncludePlayingNotes"
    /// Playing style notes are included until the player turns them off.
    public static let includePlayingNotes = true

    /// Private match notes are never included by default and the choice is
    /// never remembered, so there is deliberately no key for it.
    public static let includePrivateNotes = false
}
