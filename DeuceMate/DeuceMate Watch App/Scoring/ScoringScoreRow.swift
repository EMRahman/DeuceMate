import SwiftUI

/// The live/guide row shell. All match rules stay with the caller.
struct ScoringScoreRow<Indicator: View, Cells: View, Badge: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isMe: Bool
    let label: String
    var indicatorWidth: CGFloat = 20
    let background: Color
    let preview: Bool
    @ViewBuilder var indicator: () -> Indicator
    @ViewBuilder var cells: () -> Cells
    @ViewBuilder var badge: () -> Badge

    var body: some View {
        HStack(spacing: 4) {
            indicator().frame(width: indicatorWidth)
            Text(label).font(.headline).frame(width: 30, alignment: .leading)
            cells()
            badge()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(background)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12))))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .fill((isMe ? Color.green : Color.red).opacity(preview ? 0.22 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(preview ? (isMe ? Color.green : Color.red) : .clear, lineWidth: 3))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: preview)
    }
}

struct ScoringPointBadge: View {
    let label: String
    let background: Color
    let flashColor: Color
    let flashOpacity: Double
    var body: some View {
        Text(label)
            .font(.body.weight(.semibold))
            .frame(width: 32, alignment: .trailing)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(background.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 8).fill(flashColor.opacity(flashOpacity))))
    }
}
