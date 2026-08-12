// MatchSetupDefaults.swift — the remembered "last used" match setup (format +
// singles/doubles) that the watch start screen pre-applies so Start Match
// doesn't re-ask what almost never changes.
//
// Watch-local only (see CLAUDE.md §0): the phone never starts a live match, so
// there is no wire key and no sync handler for these two values — see
// docs/features/MATCH_START_UX_PLAN.md §5.6.
//
// Decoding is total by design: an absent, empty, or unrecognised raw value
// (e.g. a format retired in a future build) falls back rather than crashing,
// so a corrupted or stale `UserDefaults` value can never break match setup.
import Foundation

public struct MatchSetupDefaults: Sendable, Equatable {
    public static let formatKey = "defaultMatchFormat"
    public static let typeKey = "defaultMatchType"

    public let format: MatchFormat
    public let type: MatchType

    public static let fallback = MatchSetupDefaults(format: .standard, type: .singles)

    public init(format: MatchFormat, type: MatchType) {
        self.format = format
        self.type = type
    }

    /// Total decode — unknown / absent / retired raw values fall back.
    public static func resolve(formatRaw: String?, typeRaw: String?) -> MatchSetupDefaults {
        let format = formatRaw.flatMap(MatchFormat.init(rawValue:)) ?? fallback.format
        let type = typeRaw.flatMap(MatchType.init(rawValue:)) ?? fallback.type
        return MatchSetupDefaults(format: format, type: type)
    }
}
