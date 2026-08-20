// StatFormatting.swift — the count/ratio/percent strings the stats screens,
// the text export and the web export all print. Keeping one implementation is
// what makes "the web export reads the same as the archive detail" checkable
// rather than aspirational.
import Foundation

public enum StatFormatting {

    /// "76 (54%)" — a count plus its truncated share of `total`.
    /// `gap` separates the count from the parenthetical (the text export pads
    /// with two spaces for its fixed-column layout).
    public static func countAndPercent(_ count: Int, of total: Int, gap: String = " ") -> String {
        guard total > 0 else { return "0" }
        return "\(count)\(gap)(\(truncatedPercent(count, of: total))%)"
    }

    /// "3/8 (38%)" — a made/attempted ratio plus its truncated percent.
    public static func fractionAndPercent(_ numerator: Int, _ denominator: Int, gap: String = " ") -> String {
        guard denominator > 0 else { return "0/0" }
        return "\(numerator)/\(denominator)\(gap)(\(truncatedPercent(numerator, of: denominator))%)"
    }

    /// Whole percent, truncated toward zero; 0 when `total` is 0.
    public static func truncatedPercent(_ count: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(count) / Double(total)) * 100.0)
    }

    /// Whole percent, rounded to nearest; 0 when `total` is 0. Used by the
    /// points-won headers, which round rather than truncate.
    public static func roundedPercent(_ count: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(count) / Double(total) * 100).rounded())
    }
}

/// One side of a made/attempted comparison row, resolved once into the three
/// shapes the renderers need: the bar fraction, the percent text, and the raw
/// count label. Mirrored by the iOS detail view, the watch stats view and the
/// web export's comparison rows.
public struct RatioDisplay: Equatable, Sendable {
    /// 0…1 share, or 0 when nothing was attempted.
    public let fraction: Double
    /// "54%", or "—" when nothing was attempted.
    public let percentText: String
    /// "12/15", or `nil` when nothing was attempted.
    public let countText: String?

    public init(numerator: Int, denominator: Int) {
        guard denominator > 0 else {
            fraction = 0
            percentText = "—"
            countText = nil
            return
        }
        let ratio = Double(numerator) / Double(denominator)
        fraction = ratio
        percentText = "\(Int((ratio * 100).rounded()))%"
        countText = "\(numerator)/\(denominator)"
    }
}
