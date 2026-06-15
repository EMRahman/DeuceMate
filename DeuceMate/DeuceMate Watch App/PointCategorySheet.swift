// PointCategorySheet.swift
import SwiftUI
import DeuceMateCore

/// Categorization sheet shown after every scored point when stats tracking is
/// enabled. The sheet has up to two steps:
///   1. Outcome — DF / UFE / Forced / Winner. Identical to the classic flow.
///   2. Ending shot — Ace/Return/Serve · S+1 · Rally. Only shown when
///      "Detailed shot tracking" is on AND the outcome isn't a Double Fault
///      (DFs auto-lock the ending shot to `.serve`).
///
/// The sheet cannot be dismissed by the Digital Crown. The "Undo point"
/// button rolls back the entire score change AND drops any pending stat;
/// it appears on both steps because the underlying drag-to-undo gesture is
/// unreachable while the modal is up.
///
/// Tapping a button does not commit instantly: the chosen button shows a
/// checkmark and the others dim for `commitDelay`, then the selection is
/// applied. This gives a beat of visual confirmation so a mis-tap is noticed
/// (and undone) rather than silently committed.
struct PointCategorySheet: View {
    @EnvironmentObject var viewModel: ScoreViewModel
    let pending: PendingPointInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let outcome = viewModel.pendingOutcome,
           viewModel.detailedShotTrackingEnabled {
            EndingShotStep(pending: pending, outcome: outcome) { dismiss() }
        } else {
            OutcomeStep(pending: pending) { dismiss() }
        }
    }
}

// MARK: - Step 1: outcome

private struct OutcomeStep: View {
    @EnvironmentObject var viewModel: ScoreViewModel
    let pending: PendingPointInfo
    let onCommit: () -> Void

    /// The outcome the user just tapped. While set, the chosen button shows a
    /// checkmark and the others dim for a brief beat (`commitDelay`) before the
    /// selection is actually applied — visual confirmation in case of a mis-tap.
    @State private var selectedOutcome: PointOutcome?

    private var iWon: Bool { pending.winner == .me }
    private var iServed: Bool { pending.server == .me }

    private var selectableOutcomes: [PointOutcome] {
        PointOutcome.userSelectable.filter { outcome in
            guard outcome == .doubleFault else { return true }
            // Double fault only applies when the server lost on their second serve.
            return pending.isSecondServe && pending.winner != pending.server
        }
    }

    /// Outcomes chunked into rows of two so the grid lays out two buttons per
    /// row. A trailing odd button stretches to fill the full row width.
    private var outcomeRows: [[PointOutcome]] {
        stride(from: 0, to: selectableOutcomes.count, by: 2).map {
            Array(selectableOutcomes[$0..<min($0 + 2, selectableOutcomes.count)])
        }
    }

    private var bannerTint: Color {
        iWon
            ? Color(red: 0.13, green: 0.28, blue: 0.18)
            : Color(red: 0.32, green: 0.14, blue: 0.18)
    }

    private var bannerLabel: String {
        let result = iWon ? "Won" : "Lost"
        let server = iServed ? "Your serve" : "Their serve"
        return "\(result) — \(server)"
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(bannerLabel)
                    .font(.caption2.weight(.semibold))
                if pending.isSecondServe {
                    Text("2nd")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.yellow.opacity(0.85)))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8).fill(bannerTint))

            VStack(spacing: 4) {
                ForEach(Array(outcomeRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(row) { outcome in
                            Button {
                                guard selectedOutcome == nil else { return }
                                withAnimation(.easeOut(duration: 0.12)) {
                                    selectedOutcome = outcome
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + commitDelay) {
                                    viewModel.selectOutcome(outcome)
                                    if viewModel.pendingStatPoint == nil { onCommit() }
                                }
                            } label: {
                                Text(outcome.displayLabel)
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(outcome.tintColor)
                            .chosenFeedback(isChosen: selectedOutcome == outcome,
                                            anyChosen: selectedOutcome != nil)
                            .disabled(selectedOutcome != nil && selectedOutcome != outcome)
                        }
                    }
                }

                UndoPointButton {
                    viewModel.undo()
                    onCommit()
                }
                .disabled(selectedOutcome != nil)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - Step 2: ending shot

private struct EndingShotStep: View {
    @EnvironmentObject var viewModel: ScoreViewModel
    let pending: PendingPointInfo
    let outcome: PointOutcome
    let onCommit: () -> Void

    /// The ending shot the user just tapped — drives the brief "chosen"
    /// confirmation before the point is committed and the sheet dismisses.
    @State private var selectedShot: EndingShot?

    /// The header question shown above the pill buttons, tailored to the outcome.
    ///
    /// Winners and forced errors ask about the shot the *winner* played to end
    /// the point.  Unforced errors ask about the shot the *loser* played when
    /// they erred — a subtly different perspective that drives the pill choices.
    private var headerQuestion: String {
        switch outcome {
        case .winner:        return "Winning shot?"
        case .forcedError:   return "Shot that forced it?"
        case .unforcedError: return "Shot of the error?"
        default:             return "Where?"
        }
    }

    /// Contextual pill list for the ending-shot step.
    ///
    /// For **winners** and **forced errors** the pills represent the *winner's*
    /// last shot (the one that caused the point to end).
    /// For **unforced errors** the pills represent the *loser's* shot on which
    /// they made the error — a different player perspective, so the available
    /// shots differ.
    ///
    /// Server's available shots: Serve (shot 1) [winner/forced only], S+1 (shot 3), Rally (5+).
    /// Receiver's available shots: Return (shot 2), Rally (4+).
    private var pills: [(EndingShot, String)] {
        // For winners and forced errors the *winner* played the ending shot.
        // For unforced errors the *loser* played the error shot.
        // Determine whether that player was the server.
        let shotPlayerIsServer = outcome == .unforcedError
            ? pending.winner != pending.server   // loser played the error shot
            : pending.winner == pending.server   // winner played the ending shot

        if shotPlayerIsServer {
            // UFE: serve is excluded (a serve UFE is a double fault, handled separately).
            guard outcome != .unforcedError else {
                return [(.servePlusOne, "S+1"), (.rally, "Rally")]
            }
            let firstLabel = outcome == .winner ? "Ace" : "Serve"
            return [(.serve, firstLabel), (.servePlusOne, "S+1"), (.rally, "Rally")]
        } else {
            return [(.return, "Return"), (.rally, "Rally")]
        }
    }

    /// Pills chunked into rows of two so the grid lays out two buttons per row.
    /// A trailing odd pill stretches to fill the full row width.
    private var pillRows: [[(EndingShot, String)]] {
        stride(from: 0, to: pills.count, by: 2).map {
            Array(pills[$0..<min($0 + 2, pills.count)])
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 5) {
                Button {
                    viewModel.cancelOutcomeSelection()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
                .disabled(selectedShot != nil)

                Spacer()

                VStack(spacing: 1) {
                    Text(outcome.displayLabel)
                        .font(.caption2.weight(.bold))
                    Text(headerQuestion)
                        .font(.system(size: 10).weight(.regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.left")
                    .font(.caption2.weight(.semibold))
                    .opacity(0)
                    .padding(.trailing, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(outcome.tintColor.opacity(0.30))
            )

            VStack(spacing: 4) {
                ForEach(Array(pillRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.0) { (shot, label) in
                            Button {
                                guard selectedShot == nil else { return }
                                withAnimation(.easeOut(duration: 0.12)) {
                                    selectedShot = shot
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + commitDelay) {
                                    viewModel.commitEndingShot(shot)
                                    onCommit()
                                }
                            } label: {
                                Text(label)
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .chosenFeedback(isChosen: selectedShot == shot,
                                            anyChosen: selectedShot != nil)
                            .disabled(selectedShot != nil && selectedShot != shot)
                        }
                    }
                }

                UndoPointButton {
                    viewModel.undo()
                    onCommit()
                }
                .disabled(selectedShot != nil)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - Pre-warm

/// Rendered at zero size in ContentView's background so SwiftUI compiles the
/// GPU shaders for .borderedProminent buttons before the first real sheet
/// presentation, eliminating the first-point stutter. Intentionally excludes
/// ScrollView so its pan recogniser cannot steal swipe-to-score gestures.
struct PointCategorySheetPrewarm: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(PointOutcome.userSelectable) { outcome in
                Button(outcome.displayLabel) {}
                    .buttonStyle(.borderedProminent)
                    .tint(outcome.tintColor)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .clipped()
    }
}

// MARK: - Shared bits

/// How long the chosen button stays highlighted before the selection is applied
/// and the sheet advances/dismisses. Matches the changeover-overlay scheduling in
/// `ScoreViewModel.commitPointStat`, so it reads as one deliberate beat.
private let commitDelay: TimeInterval = 0.4

private extension View {
    /// Brief "you chose this" treatment: a checkmark badge on the chosen button
    /// and dimming of the others while the selection settles.
    func chosenFeedback(isChosen: Bool, anyChosen: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if isChosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .opacity(anyChosen && !isChosen ? 0.35 : 1)
    }
}

private struct UndoPointButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Undo point", systemImage: "arrow.uturn.left")
                .font(.caption2)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.gray)
        .padding(.top, 2)
    }
}
