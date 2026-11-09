import SwiftUI

/// Observe the workout manager directly; sensor ticks need not redraw the scorer.
struct WorkoutStatusView: View {
    @ObservedObject var manager: WorkoutManager

    var body: some View {
        if let message = manager.workoutError {
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Button("Dismiss") { manager.workoutError = nil }
                    .font(.caption2)
            }
            .accessibilityElement(children: .contain)
        }
    }
}
