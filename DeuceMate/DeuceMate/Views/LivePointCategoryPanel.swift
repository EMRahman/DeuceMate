// LivePointCategoryPanel.swift — iPhone-side mirror of the watch's
// PointCategorySheet. Lets a spectator finish post-point stat entry from the
// phone when iPhone Input is enabled. The watch remains source of truth: every
// tap fires a stat-action command to the watch, which validates, applies via
// its existing categorization paths, and pushes the new pending state back.
import SwiftUI
import DeuceMateCore

extension PointOutcome {
    fileprivate static let tintDoubleFault   = Color(red: 0.86, green: 0.36, blue: 0.36)
    fileprivate static let tintWinner        = Color(red: 0.30, green: 0.78, blue: 0.50)
    fileprivate static let tintForcedError   = Color(red: 0.92, green: 0.70, blue: 0.30)
    fileprivate static let tintUnforcedError = Color(red: 0.66, green: 0.50, blue: 0.92)

    var liveTintColor: Color {
        switch self {
        case .doubleFault:   return PointOutcome.tintDoubleFault
        case .winner:        return PointOutcome.tintWinner
        case .forcedError:   return PointOutcome.tintForcedError
        case .unforcedError: return PointOutcome.tintUnforcedError
        case .uncategorized: return .gray
        }
    }
}

/// Bottom panel overlaid on the live scoreboard while a point is awaiting
/// categorization on the watch. Renders the same two-step flow as
/// `PointCategorySheet`:
///   1. Outcome — DF / UFE / Forced / Winner.
///   2. Ending shot — Serve/Return · S+1 · Rally (skipped when detailed shot
///      tracking is off or the outcome is a Double Fault).
///
/// Tapping any action sends a control message to the watch; the panel
/// dismisses itself once the watch echoes back the resulting pending state
/// (cleared = sheet down, advanced = phase 2). Optimistic local state is
/// intentionally avoided so the two devices never diverge on what stage of
/// categorization is current.
struct LivePointCategoryPanel: View {
    let pending: PendingPointInfo
    let outcome: PointOutcome?
    let detailedShotTrackingEnabled: Bool
    let onSelectOutcome: (PointOutcome) -> Void
    let onCommitEndingShot: (EndingShot) -> Void
    let onCancelOutcome: () -> Void
    let onUndoPoint: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let outcome, detailedShotTrackingEnabled, outcome != .doubleFault {
                endingShotStep(outcome: outcome)
            } else {
                outcomeStep
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.18))
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 8)
        .frame(maxWidth: 720)
    }

    // MARK: - Step 1: outcome

    private var outcomeStep: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                bannerLabel
                Spacer()
                undoButton
            }

            HStack(spacing: 10) {
                ForEach(selectableOutcomes) { outcome in
                    Button {
                        onSelectOutcome(outcome)
                    } label: {
                        Text(outcome.displayLabel)
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(outcome.liveTintColor)
                }
            }
        }
    }

    private var selectableOutcomes: [PointOutcome] {
        PointOutcome.userSelectable.filter { outcome in
            guard outcome == .doubleFault else { return true }
            // Double fault only applies when the server lost on their second serve.
            return pending.isSecondServe && pending.winner != pending.server
        }
    }

    private var bannerLabel: some View {
        let iWon = pending.winner == .me
        let iServed = pending.server == .me
        let result = iWon ? "Won" : "Lost"
        let server = iServed ? "Your serve" : "Their serve"
        let tint: Color = iWon
            ? Color(red: 0.13, green: 0.28, blue: 0.18)
            : Color(red: 0.32, green: 0.14, blue: 0.18)
        return HStack(spacing: 8) {
            Text("\(result) — \(server)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            if pending.isSecondServe {
                Text("2nd")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.85)))
                    .foregroundStyle(.black)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint))
    }

    // MARK: - Step 2: ending shot

    @ViewBuilder
    private func endingShotStep(outcome: PointOutcome) -> some View {
        let pills = endingShotPills(for: outcome)
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    onCancelOutcome()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 1) {
                    Text(outcome.displayLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(headerQuestion(for: outcome))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                undoButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(outcome.liveTintColor.opacity(0.28))
            )

            HStack(spacing: 10) {
                ForEach(pills, id: \.0) { shot, label in
                    Button {
                        onCommitEndingShot(shot)
                    } label: {
                        Text(label)
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
        }
    }

    private func headerQuestion(for outcome: PointOutcome) -> String {
        switch outcome {
        case .winner:        return "Winning shot?"
        case .forcedError:   return "Shot that forced it?"
        case .unforcedError: return "Shot of the error?"
        default:             return "Where?"
        }
    }

    /// Same context-aware pill routing as `PointCategorySheet.EndingShotStep`.
    /// Keep these in sync if shot-attribution logic changes on the watch.
    private func endingShotPills(for outcome: PointOutcome) -> [(EndingShot, String)] {
        let shotPlayerIsServer = outcome == .unforcedError
            ? pending.winner != pending.server
            : pending.winner == pending.server

        if shotPlayerIsServer {
            guard outcome != .unforcedError else {
                return [(.servePlusOne, "S+1"), (.rally, "Rally")]
            }
            let firstLabel = outcome == .winner ? "Ace" : "Serve"
            return [(.serve, firstLabel), (.servePlusOne, "S+1"), (.rally, "Rally")]
        } else {
            return [(.return, "Return"), (.rally, "Rally")]
        }
    }

    private var undoButton: some View {
        Button(action: onUndoPoint) {
            Label("Undo", systemImage: "arrow.uturn.left")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
        .tint(.gray)
    }
}
