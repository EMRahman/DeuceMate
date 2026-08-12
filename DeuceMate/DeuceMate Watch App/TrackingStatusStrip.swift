// TrackingStatusStrip.swift — the "what will this match record?" row shown on
// the watch start screen, directly under Start Match.
//
// Point tracking, Health access, and Pulse Coach calibration are all set once
// and then invisible, yet they decide whether a finished match is rich or thin
// — and none of them can be fixed after the fact. The strip states all three
// before the first point, and taps through to Settings so the answer is one
// tap from the fix. What each chip says comes from `MatchTrackingStatus` in
// DeuceMateCore; this file only paints it.
import SwiftUI
import DeuceMateCore

/// Colour language shared by the strip and the settings summary rows:
/// green = recording, orange = recording but degraded, grey = not recording.
extension TrackingReadiness {
    var tint: Color {
        switch self {
        case .on:      return .green
        case .partial: return .orange
        case .off:     return .gray
        }
    }
}

/// Live-bound strip for the start screen. `ScoreViewModel` forwards
/// `WorkoutManager.objectWillChange` into its own (see `ScoreViewModel.init`),
/// so observing the view model alone is enough to redraw when Health access
/// changes. Collapses Pulse Coach out when Health is off (OQ-1).
struct LiveTrackingStatusStrip: View {
    @ObservedObject var viewModel: ScoreViewModel
    let action: () -> Void

    var body: some View {
        TrackingStatusStrip(
            statuses: MatchTrackingStatus.collapsingPulseWhenHealthOff(viewModel.trackingStatuses),
            action: action
        )
    }
}

/// Live-bound rows for the Settings sheet — always all three (see
/// `TrackingStatusRows`), same observation note as above.
struct LiveTrackingStatusRows: View {
    @ObservedObject var viewModel: ScoreViewModel

    var body: some View {
        TrackingStatusRows(statuses: viewModel.trackingStatuses)
    }
}

struct TrackingStatusStrip: View {
    let statuses: [MatchTrackingStatus]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ForEach(statuses, id: \.facet) { status in
                    TrackingStatusChip(status: status)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            statuses.map(\.accessibilityDescription).joined(separator: " ")
        )
        .accessibilityHint("Opens Settings")
        .accessibilityAddTraits(.isButton)
    }
}

/// One chip: icon + state on a single line — the word ("Points", "Health") is
/// redundant next to the icon at this size, and the full name lives in the
/// Settings rows below.
private struct TrackingStatusChip: View {
    let status: MatchTrackingStatus

    private var tint: Color { status.readiness.tint }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(status.stateLabel)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        )
    }
}

/// The same three statuses as full-width rows, used at the top of the watch
/// Settings sheet where there is room for the explanation — including the one
/// setting with no in-app toggle (Health), whose only fix lives on the iPhone.
/// Always shows all three, even when the strip above has collapsed Pulse away
/// (§4.3's mitigation: the complete picture stays one tap away).
struct TrackingStatusRows: View {
    let statuses: [MatchTrackingStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(statuses, id: \.facet) { status in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: status.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(status.readiness.tint)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(status.title)
                            Spacer()
                            Text(status.stateLabel)
                                .fontWeight(.semibold)
                                .foregroundStyle(status.readiness.tint)
                        }
                        // LocalizedStringKey (not the plain-String initializer)
                        // so the Pulse "Est." detail's **bold** clause renders —
                        // Text(String) does not parse Markdown.
                        Text(LocalizedStringKey(status.detail))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status.accessibilityDescription)
            }
        }
    }
}
