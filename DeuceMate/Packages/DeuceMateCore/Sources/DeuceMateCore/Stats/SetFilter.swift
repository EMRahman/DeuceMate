// SetFilter.swift — the "All / per-set" scope both stats screens, the text
// export and the web export slice a match by. The label rule (a deciding
// super-tiebreak reads "TB", every other set reads by number) previously lived
// in three private copies that could drift independently.
import Foundation

public enum SetFilter: Hashable, Sendable {
    case all
    case set(Int)

    /// Width of the rendered set label. The watch uses `.short` ("S2") because
    /// the picker row is a few points wide; the phone and web use `.long`.
    public enum LabelStyle: Sendable {
        case long
        case short
    }

    public func label(matchFormat: MatchFormat, style: LabelStyle = .long) -> String {
        switch self {
        case .all:
            return "All"
        case .set(let index):
            if matchFormat.config.isDecidingSuperTiebreak(setIndex: index) { return "TB" }
            return style == .long ? "Set \(index + 1)" : "S\(index + 1)"
        }
    }

    /// The set indices this filter covers in a match holding `setCount` sets.
    public func setIndices(setCount: Int) -> [Int] {
        switch self {
        case .all: return Array(0..<setCount)
        case .set(let index): return [index]
        }
    }

    /// `nil` for `.all`, otherwise the selected set — the shape used by APIs
    /// that take an optional set index (`MatchWebViewModel`, `SetActivitySplit`).
    public var setIndex: Int? {
        switch self {
        case .all: return nil
        case .set(let index): return index
        }
    }

    /// `.all` followed by one filter per set — the picker's contents.
    public static func filters(setCount: Int) -> [SetFilter] {
        [.all] + (0..<setCount).map(SetFilter.set)
    }
}
