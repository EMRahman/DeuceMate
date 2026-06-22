// WebExportColors.swift — single source of truth for the colours/symbols the
// self-contained HTML match export draws with. Kept in step with the visual
// language of the SwiftUI charts (`PointsGraphView.swift`) so the browser
// viewer never re-encodes the palette: Swift emits hex, the JS just paints it.
//
// Values are Apple's standard system colours (the SwiftUI `.orange`, `.yellow`,
// … used by the charts) expressed as hex, plus the default theme's me/opponent
// line colours.
import Foundation

public enum WebExportColors {

    // MARK: - Point outcome scatter (mirrors PointsGraphView outcome colours/symbols)

    /// Hex colour for a point outcome's scatter mark.
    public static func outcomeColorHex(_ outcome: PointOutcome) -> String {
        switch outcome {
        case .doubleFault:   return "#FF9500" // orange
        case .winner:        return "#FFCC00" // yellow
        case .unforcedError: return "#FF3B30" // red
        case .forcedError:   return "#AF52DE" // purple
        case .uncategorized: return "#8E8E93" // gray
        }
    }

    /// Symbol key for a point outcome (interpreted by the viewer JS).
    public static func outcomeSymbol(_ outcome: PointOutcome) -> String {
        switch outcome {
        case .doubleFault:   return "square"
        case .winner:        return "circle"
        case .unforcedError: return "cross"
        case .forcedError:   return "triangle"
        case .uncategorized: return "circle"
        }
    }

    /// Short chart label for a point outcome (matches PointsGraphView legend).
    public static func outcomeShortLabel(_ outcome: PointOutcome) -> String {
        switch outcome {
        case .doubleFault:   return "DF"
        case .winner:        return "W"
        case .unforcedError: return "UE"
        case .forcedError:   return "FE"
        case .uncategorized: return "—"
        }
    }

    // MARK: - Ending-shot scatter (mirrors PointsGraphView ending-shot colours/symbols)

    public static func endingShotColorHex(_ shot: EndingShot) -> String {
        switch shot {
        case .serve:        return "#30B0C7" // teal
        case .return:       return "#5856D6" // indigo
        case .servePlusOne: return "#00C7BE" // mint
        case .rally:        return "#A2845E" // brown
        }
    }

    public static func endingShotSymbol(_ shot: EndingShot) -> String {
        switch shot {
        case .serve:        return "pentagon"
        case .return:       return "asterisk"
        case .servePlusOne: return "plus"
        case .rally:        return "triangle"
        }
    }

    // MARK: - Set bands (mirrors PointsGraphView SetBand fills)

    /// Solid fill hex for a set band; combine with `setBandOpacity` for the wash.
    public static func setBandColorHex(setNumber: Int, isTiebreak: Bool) -> String {
        if isTiebreak { return "#FFCC00" } // yellow
        switch setNumber {
        case 1:  return "#007AFF" // blue
        case 2:  return "#FF9500" // orange
        case 3:  return "#AF52DE" // purple
        default: return "#8E8E93" // gray
        }
    }

    public static func setBandOpacity(isTiebreak: Bool) -> Double {
        isTiebreak ? 0.22 : 0.10
    }

    // MARK: - Momentum lines + overlays (default theme me/opponent colours)

    /// Default theme "me" line colour (rgb 0.20, 0.76, 0.51).
    public static let meLineHex = "#33C282"
    /// Default theme "opponent" line colour (rgb 0.26, 0.54, 0.93).
    public static let opponentLineHex = "#428AED"
    /// Heart-rate overlay line (system red).
    public static let hrLineHex = "#FF3B30"
    /// Steps overlay line (system green).
    public static let stepsLineHex = "#34C759"
}
