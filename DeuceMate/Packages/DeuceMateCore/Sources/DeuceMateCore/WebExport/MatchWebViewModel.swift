// MatchWebViewModel.swift — pure, Encodable, platform-neutral flattening of one
// `MatchRecord` (plus both `MatchStatsSummary` perspectives and a
// perspective-neutral point list) into the clean JSON shape that the
// self-contained HTML viewer renders from.
//
// ALL derivation lives here in tested Swift — the embedded browser JS only
// paints what this produces. Heart-rate / steps / distance / calories are the
// RECORDER's physiology and appear only in the `me` perspective + the
// recorder-only `hr`/`steps`/`meta.totals` blocks; the `opponent` perspective is
// HR-free (mirrors `MatchExporter`'s rule).
import Foundation

public struct MatchWebViewModel: Encodable, Sendable {

    /// Wire-contract version for the viewer JS. Bump when the shape changes.
    /// v2 added the TV-style `comparison` block + dropped the viewer's
    /// perspective toggle in favour of a fixed recorder-framed page. v3 replaced
    /// the single `comparison` with per-set-filter `filters` (All / Set N) and
    /// added the Stats/Points tabs + point-display fields. v4 added the optional
    /// `aiCoach` block (AI coaching prompt + launch links). v5 added the
    /// `perPoint` field to each steps sample (Total vs Per-point overlay mode).
    public static let currentSchemaVersion = 5

    public let schemaVersion: Int
    public let generatedAt: String
    public let meta: Meta
    public let perspectives: Perspectives
    public let points: [PointVM]
    public let setBands: [SetBandVM]
    /// Recorder-only. Present only when heart-rate data exists.
    public let hr: HRBlock?
    /// Recorder-only. Present only when per-point cumulative step data exists.
    public let steps: StepsBlock?
    public let palette: Palette
    /// Per-set-filter stat views (`All`, `Set 1`, `Set 2`, …) — each carries the
    /// TV-style Me-vs-Opponent `comparison` (mirrors `MatchDetailView`'s split
    /// bars), the points-won header, and the duration/activity rows for that
    /// filter. `filters[0]` is always `All`; the viewer's set picker appears only
    /// when there is more than one set (i.e. `filters.count > 2`).
    public let filters: [FilterVM]
    /// Label per set index (`Set 1` / `TB`), for the Points-tab group headers.
    public let setLabels: [String]
    /// AI coaching prompt + launch links (mirrors the iOS `AICoachSheet`).
    /// Present only when the caller supplies a prompt (the iOS share path does);
    /// `nil` for a bare `MatchHTMLExporter.html(for:)` with no prompt injected.
    public let aiCoach: AICoach?

    // MARK: - Nested types

    public struct Meta: Encodable, Sendable {
        public let dateISO: String
        public let dateDisplay: String
        public let formatLabel: String
        public let matchTypeLabel: String
        public let isDoubles: Bool
        public let durationSeconds: Int
        public let durationDisplay: String
        public let sets: [SetVM]
        /// Recorder-only HealthKit totals; shown by the viewer only in `me` view.
        public let totals: Totals?
    }

    public struct SetVM: Encodable, Sendable {
        public let setNumber: Int
        public let scoreMe: String       // recorder-perspective score, e.g. "6–4" or "7–5 (7–3)"
        public let scoreOpponent: String // opponent-perspective score (swapped)
        public let durationSeconds: Int
        public let durationDisplay: String?
    }

    public struct Totals: Encodable, Sendable {
        public let steps: Int?
        public let stepsDisplay: String?
        public let distanceDisplay: String?
        public let caloriesDisplay: String?
    }

    public struct Perspectives: Encodable, Sendable {
        public let me: PerspectiveVM
        public let opponent: PerspectiveVM
    }

    public struct PerspectiveVM: Encodable, Sendable {
        public let result: String        // "won" | "lost" | "draw" | "inProgress"
        public let scoreDisplay: String
        public let totalPoints: Int
        public let pointsWon: Int
        public let pointsLost: Int
        public let hasOutcomes: Bool
        public let sections: [StatSection]
        /// Per-outcome occurrence counts attributed to this perspective's player
        /// (keyed by `PointOutcome` raw value), shown on the chart's "Me" outcome
        /// pills — mirrors the focal-player counts on `PointsGraphView`'s pills.
        public let outcomeCounts: [String: Int]
        /// Per-outcome counts attributed to the *other* player, shown on the
        /// chart's "Opp" outcome pills (mirrors PointsGraphView's `oppOutcomeCounts`).
        public let outcomeCountsOpponent: [String: Int]
        /// Points this perspective's player *won*, bucketed by the ending shot
        /// phase (keyed by `EndingShot` raw value) — drives the "Won" ending-shot
        /// pills. Mirrors PointsGraphView's `endingWonByPhase`.
        public let endingWonByPhase: [String: Int]
        /// Points this perspective's player *lost*, bucketed by ending shot phase —
        /// drives the "Lost" ending-shot pills. Mirrors `endingLostByPhase`.
        public let endingLostByPhase: [String: Int]
        /// Ending-shot phases that actually occurred this match (won + lost > 0),
        /// in rally order (`EndingShot.allCases`). Empty hides the ending-shot
        /// controls, mirroring PointsGraphView's `presentEndingPhases`.
        public let presentEndingPhases: [String]
        /// PulseCoach (HR-derived) insights — recorder-only; nil on opponent.
        public let pulseInsights: [String]?
    }

    public struct StatSection: Encodable, Sendable {
        public let title: String
        public let rows: [StatRow]
        /// Free-text note rendered above the rows (e.g. partial-data warning).
        public let note: String?
        /// A section that is purely a bullet list (coaching insights).
        public let bullets: [String]?
    }

    public struct StatRow: Encodable, Sendable {
        public let label: String
        public let value: String
        public let hint: String?
        /// Fill fraction (0…1) driving the percentage bar; `nil` for plain-count
        /// rows that have no meaningful percentage. The `value` string still
        /// carries the raw counts (e.g. "67% (12/15)").
        public let fraction: Double?

        public init(label: String, value: String, hint: String? = nil, fraction: Double? = nil) {
            self.label = label
            self.value = value
            self.hint = hint
            self.fraction = fraction
        }
    }

    public struct PointVM: Encodable, Sendable {
        public let index: Int            // 0-based match order
        public let setIndex: Int
        public let server: String        // "me" | "opp" (recorder perspective)
        public let winner: String        // "me" | "opp"
        public let outcome: String       // PointOutcome raw value
        public let outcomeLabel: String
        public let outcomeColorHex: String
        public let outcomeSymbol: String
        // Points-tab display (mirrors MatchDetailView.pointRow): the short chip
        // (W / Opp W / DF / UE / FE / + / −) coloured by attribution, the longer
        // outcome line ("Winner — Me"), and the server-relative game-score label
        // ("0–15", "Deuce", "Ad Me"). Distinct from `gameScoreLabel`, which is the
        // server–returner notation the chart popup uses.
        public let chipText: String
        public let chipColorHex: String
        public let outcomeText: String
        public let pointScoreLabel: String
        public let endingShot: String?   // EndingShot raw value
        public let endingShotLabel: String?
        public let endingShotColorHex: String?
        public let endingShotSymbol: String?
        public let isSecondServe: Bool
        public let isBreakPoint: Bool
        public let gameScoreLabel: String
        public let cumulativeMe: Int
        public let cumulativeOpp: Int
        public let heartRateBPM: Int?    // recorder's HR
        public let stepsCumulative: Int?
    }

    public struct SetBandVM: Encodable, Sendable {
        public let setNumber: Int
        public let isTiebreak: Bool
        public let startIndex: Int
        public let endIndex: Int
        public let colorHex: String
        public let opacity: Double
        public let label: String
    }

    public struct HRBlock: Encodable, Sendable {
        public struct Sample: Encodable, Sendable {
            public let pointIndex: Int
            public let bpm: Int
            public let setIndex: Int
            public let wonByMe: Bool
        }
        public struct Zone: Encodable, Sendable {
            public let label: String
            public let descriptiveLabel: String
            public let total: Int
            public let wins: Int
            public let winPct: String
            public let colorHex: String
        }
        public let timeline: [Sample]
        public let zones: [Zone]
        public let resolvedMaxHR: Int
    }

    public struct StepsBlock: Encodable, Sendable {
        public struct Sample: Encodable, Sendable {
            public let pointIndex: Int
            public let cumulative: Int
            public let perPoint: Int
        }
        public let timeline: [Sample]
    }

    public struct Palette: Encodable, Sendable {
        public struct Legend: Encodable, Sendable {
            public let key: String
            public let label: String
            public let colorHex: String
            public let symbol: String
        }
        public let meLineHex: String
        public let opponentLineHex: String
        public let hrLineHex: String
        public let stepsLineHex: String
        public let outcomes: [Legend]
        public let endingShots: [Legend]
    }

    // MARK: - Set-filtered stat views (mirrors MatchDetailView's set picker)

    public struct FilterVM: Encodable, Sendable {
        public let key: String        // "all" | "set-0" | "set-1" …
        public let label: String      // "All" | "Set 1" | "TB"
        public let pointsWon: PointsWonVM
        /// Duration + Steps/Calories rows for this filter (recorder activity).
        public let durationRows: [LabeledValue]
        public let comparison: Comparison
    }

    public struct PointsWonVM: Encodable, Sendable {
        public let meWon: Int
        public let oppWon: Int
        public let total: Int
        public let mePct: Int
        public let oppPct: Int
    }

    public struct LabeledValue: Encodable, Sendable {
        public let label: String
        public let value: String
    }

    // MARK: - AI coaching (mirrors the iOS AICoachSheet)

    public struct AICoach: Encodable, Sendable {
        public let title: String          // "Get AI Coaching Tips"
        public let intro: String          // one-line explanation
        public let mePrompt: String
        /// Opponent-perspective prompt; `nil` hides the My/Opponent toggle.
        public let opponentPrompt: String?
        /// The AI apps the viewer offers a one-tap launch link to.
        public let apps: [App]

        public struct App: Encodable, Sendable {
            public let name: String
            public let url: String        // launch URL (https://…)
            public let colorHex: String
            /// When true the viewer appends `?q=<prompt>` to pre-fill the chat.
            public let supportsPromptParam: Bool
        }
    }

    // MARK: - TV-style comparison (mirrors MatchDetailView's split-bar stats)

    public struct Comparison: Encodable, Sendable {
        /// At least one categorised point exists (gates the Outcome Breakdown).
        public let hasAnyOutcomeData: Bool
        public let sections: [CmpSection]
        /// Footer note about uncategorised points excluded from outcome stats.
        public let note: String?
    }

    public struct CmpSection: Encodable, Sendable {
        public let title: String
        public let rows: [CmpRow]
        /// Rendered in place of rows (e.g. the "not collected" placeholder).
        public let placeholder: String?
    }

    public struct CmpRow: Encodable, Sendable {
        /// `percent` → split bars + inner count; `count` → bars scaled to the
        /// larger side; `ratio` → bare me/opp values, no bar (W:UE).
        public enum Kind: String, Encodable, Sendable { case percent, count, ratio }
        public let label: String
        public let subtitle: String?
        public let kind: Kind
        public let meValue: String       // "67%", "3", or "1.5 : 1"
        public let oppValue: String
        public let meFraction: Double    // 0…1 bar fill
        public let oppFraction: Double
        public let meBarLabel: String?   // inner count, e.g. "12/15" (percent rows)
        public let oppBarLabel: String?
    }

    // MARK: - Builder

    /// Build the view model for one match. `maxHR` is used for HR-zone bucketing
    /// (recorder-only). Both `me` and `opponent` perspectives are computed.
    /// `aiPromptMe` / `aiPromptOpponent` are the pre-generated AI coaching prompts
    /// (from `MatchExporter`); supply them to surface the AI Coach card.
    public nonisolated static func make(from record: MatchRecord, maxHR: Int = 190,
                                        aiPromptMe: String? = nil,
                                        aiPromptOpponent: String? = nil) -> MatchWebViewModel {
        let allStats = record.stats
        let hasStats = !allStats.isEmpty
        let categorized = allStats.filter { $0.outcome != .uncategorized }
        let hasOutcomes = !categorized.isEmpty
        let mixed = hasOutcomes && categorized.count < allStats.count

        // Full summary (all points) drives point totals; categorized subset drives
        // outcome-derived sections — mirrors MatchExporter.dataSections.
        func summary(_ stats: [PointStat], focal: Player) -> MatchStatsSummary {
            MatchStatsSummary(stats: stats, focal: focal,
                              setElapsedSeconds: record.setElapsedSeconds, maxHR: maxHR)
        }
        let fullMe  = summary(allStats, focal: .me)
        let fullOpp = summary(allStats, focal: .opponent)
        let catMe   = hasOutcomes ? summary(categorized, focal: .me) : fullMe
        let catOpp  = hasOutcomes ? summary(categorized, focal: .opponent) : fullOpp

        // Meta
        let durationSecs = Self.durationSeconds(record)
        let meta = Meta(
            dateISO: Self.isoFormatter.string(from: record.startTime),
            dateDisplay: Self.displayFormatter.string(from: record.startTime),
            formatLabel: Self.formatLabel(record),
            matchTypeLabel: record.matchType == .doubles ? "Doubles" : "Singles",
            isDoubles: record.matchType == .doubles,
            durationSeconds: Int(durationSecs),
            durationDisplay: durationSecs > 0 ? Self.minutesString(durationSecs) : "—",
            sets: Self.setRows(record),
            totals: Self.totals(record)
        )

        // Perspectives
        let me = Self.perspective(
            record: record, focal: .me, full: fullMe, categorized: catMe,
            hasStats: hasStats, hasOutcomes: hasOutcomes, mixed: mixed,
            categorizedCount: categorized.count, totalCount: allStats.count
        )
        let opponent = Self.perspective(
            record: record, focal: .opponent, full: fullOpp, categorized: catOpp,
            hasStats: hasStats, hasOutcomes: hasOutcomes, mixed: mixed,
            categorizedCount: categorized.count, totalCount: allStats.count
        )

        // Points + set bands
        let points = Self.pointRows(allStats)
        let setBands = Self.setBands(points)

        // Recorder-only HR / steps blocks (from the `me` full summary).
        let hrBlock = Self.hrBlock(fullMe)
        let stepsBlock = Self.stepsBlock(stats: allStats, totalSteps: record.totalSteps)

        let palette = Palette(
            meLineHex: WebExportColors.meLineHex,
            opponentLineHex: WebExportColors.opponentLineHex,
            hrLineHex: WebExportColors.hrLineHex,
            stepsLineHex: WebExportColors.stepsLineHex,
            outcomes: PointOutcome.userSelectable.map {
                Palette.Legend(key: $0.rawValue,
                               label: WebExportColors.outcomeShortLabel($0),
                               colorHex: WebExportColors.outcomeColorHex($0),
                               symbol: WebExportColors.outcomeSymbol($0))
            },
            endingShots: EndingShot.allCases.map {
                Palette.Legend(key: $0.rawValue,
                               label: $0.displayLabel,
                               colorHex: WebExportColors.endingShotColorHex($0),
                               symbol: WebExportColors.endingShotSymbol($0))
            }
        )

        // Per-set-filter stat views (All + one per set), each with its own
        // TV-style comparison, points-won header, and duration/activity rows —
        // matches MatchDetailView's set picker recomputing meSummary/oppSummary
        // over the filtered stats.
        let filters = Self.buildFilters(record, maxHR: maxHR)
        let setLabels = record.setScores.indices.map { Self.setLabel(record, $0) }
        let aiCoach = Self.buildAICoach(mePrompt: aiPromptMe, opponentPrompt: aiPromptOpponent)

        return MatchWebViewModel(
            schemaVersion: currentSchemaVersion,
            generatedAt: Self.isoFormatter.string(from: Date()),
            meta: meta,
            perspectives: Perspectives(me: me, opponent: opponent),
            points: points,
            setBands: setBands,
            hr: hrBlock,
            steps: stepsBlock,
            palette: palette,
            filters: filters,
            setLabels: setLabels,
            aiCoach: aiCoach
        )
    }
}
