/// Watch scoring gestures. Callers retain their own match/modal guards.
public enum ScoreInputAction: Equatable, Sendable {
    case win, lose, undo, stats

    public static func drag(horizontal: Double, vertical: Double) -> Self? {
        if abs(horizontal) > abs(vertical) {
            if horizontal < -20 { return .undo }
            if horizontal > 40 && abs(horizontal) > 2 * abs(vertical) { return .stats }
        } else {
            if vertical < -20 { return .win }
            if vertical > 20 { return .lose }
        }
        return nil
    }

    public var label: String {
        switch self {
        case .win: return "Win point"
        case .lose: return "Lose point"
        case .undo: return "Undo point"
        case .stats: return "Open live stats"
        }
    }

    public var instruction: String {
        switch self {
        case .win: return "Swipe up"
        case .lose: return "Swipe down"
        case .undo: return "Swipe left to undo"
        case .stats: return "Swipe right for live stats"
        }
    }
}
