// LiveWatchPromptPanel.swift — iPhone-side mirror of the Watch screens that
// pause play: the changeover reminder ("Even games – balls change ends") and
// doubles' "Who serves next?". Lets the person scoring on the iPhone answer
// them while the player wears the Watch.
//
// The Watch stays the source of truth. Each button sends a prompt answer;
// the Watch applies it with the same method as its own button (so its overlay
// clears too) and replies with the saved state. Nothing changes here until
// that reply arrives, so the two screens can never disagree.
import SwiftUI
import DeuceMateCore

struct LiveWatchPromptPanel: View {
    let prompt: LiveWatchPrompt
    let status: LiveScoreboardStatus
    let onAnswer: (LiveWatchPrompt.Answer) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)
                Text(prompt.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            if let detail = prompt.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            // A spectator (iPhone Input off) sees what the Watch is asking
            // but gets no buttons that could never send.
            if status.isInputEnabled {
                HStack(spacing: 10) {
                    ForEach(prompt.answers) { answer in
                        Button {
                            onAnswer(answer)
                        } label: {
                            Text(answer.label)
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                        .accessibilityIdentifier("live-prompt-answer-\(answer.id)")
                    }
                }
                .disabled(!status.acceptsPromptAnswer)
            }
            if let caption = status.promptCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
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
        .frame(maxWidth: 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live-watch-prompt")
    }

    /// Green like the Watch's OK; the doubles choice uses the Watch's team
    /// buttons' neutral blue.
    private var tint: Color {
        prompt.kind == .changeover ? .green : .blue
    }
}
