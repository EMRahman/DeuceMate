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

/// Live-bound strip for the start screen. Observes the `WorkoutManager`
/// directly as well as the view model: Health access lives on the workout
/// manager and `ScoreViewModel` does not republish it.
struct LiveTrackingStatusStrip: View {
    @ObservedObject var viewModel: ScoreViewModel
    @ObservedObject var workoutManager: WorkoutManager
    let action: () -> Void

    var body: some View {
        TrackingStatusStrip(statuses: viewModel.trackingStatuses, action: action)
    }
}

/// Live-bound rows for the Settings sheet. Same observation note as above.
struct LiveTrackingStatusRows: View {
    @ObservedObject var viewModel: ScoreViewModel
    @ObservedObject var workoutManager: WorkoutManager

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

private struct TrackingStatusChip: View {
    let status: MatchTrackingStatus

    private var tint: Color { status.readiness.tint }

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: status.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(status.shortTitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(status.stateLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
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
                        Text(status.detail)
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
