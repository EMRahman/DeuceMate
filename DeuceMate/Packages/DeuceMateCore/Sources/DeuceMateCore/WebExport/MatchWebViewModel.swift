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
    public static let currentSchemaVersion = 1

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

    // MARK: - Builder

    /// Build the view model for one match. `maxHR` is used for HR-zone bucketing
    /// (recorder-only). Both `me` and `opponent` perspectives are computed.
    public nonisolated static func make(from record: MatchRecord, maxHR: Int = 190) -> MatchWebViewModel {
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
        let stepsBlock = Self.stepsBlock(points)

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

        return MatchWebViewModel(
            schemaVersion: currentSchemaVersion,
            generatedAt: Self.isoFormatter.string(from: Date()),
            meta: meta,
            perspectives: Perspectives(me: me, opponent: opponent),
            points: points,
            setBands: setBands,
            hr: hrBlock,
            steps: stepsBlock,
            palette: palette
        )
    }
}
