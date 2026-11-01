// MatchInfoSection.swift — the "Match Info" block under MatchDetailView's
// header: who was played and the competition type, a private-notes preview,
// and the entry to "Compare with previous match". See MATCH_TAGS_PLAN.md §7.1.
//
// Editing is available for completed AND in-progress archived records and
// never touches the score or completion. A watch-only row (not yet in the
// iPhone archive) must be synced to the iPhone first.
import SwiftUI
import DeuceMateCore

struct MatchInfoSection: View {
    let record: MatchRecord
    /// Whether the record is in the iPhone archive (only those can be edited).
    let isInArchive: Bool
    /// The editors are presented by the hosting view, not from inside the
    /// List: a `.sheet` attached to a lazily managed List section/row does
    /// not reliably present.
    @Binding var showEditor: Bool
    @Binding var showNotesEditor: Bool

    @EnvironmentObject private var store: PhoneStatsStore
    @ObservedObject private var notesStore: MatchNotesStore = .shared
    /// Phone-local presentation preference, shared across matches.
    @AppStorage("matchInfoExpanded") private var isExpanded = false

    var body: some View {
        Section {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    Text(record.tags?.displayLine ?? "Add match details")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if notesStore.note(for: record.id) != nil {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Match Info, \(record.tags?.displayLine ?? "Add match details")\(notesStore.note(for: record.id) != nil ? ", private note saved" : "")")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hide match details" : "Show editing, notes and comparison")
            .accessibilityIdentifier("match-info-disclosure")

            if isExpanded {
                matchInfoRow
                notesRow
                NavigationLink {
                    MatchComparisonView(currentID: record.id)
                } label: {
                    Label("Compare with Previous Match", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("compare-previous-match")
            }
        } header: {
            Text("Match Info")
        } footer: {
            if !isInArchive {
                Text("Sync this match to iPhone to add an opponent, competition type or notes.")
            }
        }
    }

    // MARK: - Rows

    private var matchInfoRow: some View {
        Button {
            showEditor = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: record.matchType == .doubles ? "person.2.fill" : "person.fill")
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    if record.tags?.displayLine != nil {
                        // Who on the first line, competition below, so a long
                        // doubles line never wraps mid-caption.
                        if let who = whoLine {
                            Text(who)
                                .foregroundStyle(.primary)
                        }
                        if let competition = record.tags?.competitionType {
                            Text(competition.displayLabel)
                                .font(whoLine == nil ? .body : .subheadline)
                                .foregroundStyle(whoLine == nil ? .primary : .secondary)
                        }
                        if let headToHead = headToHeadLine {
                            Text(headToHead)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(record.matchType == .doubles ? "Add players & type" : "Add opponent & type")
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInArchive)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(matchInfoAccessibilityLabel)
        .accessibilityIdentifier("match-info-row")
        .accessibilityHint("Edit who you played and the competition type")
    }

    @ViewBuilder
    private var notesRow: some View {
        let note = notesStore.note(for: record.id)
        Button {
            showNotesEditor = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "note.text")
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    if let note {
                        Text(note.text)
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                        Text("Private note · on this iPhone only")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add private note")
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInArchive)
        .accessibilityIdentifier("match-notes-row")
    }

    /// "With Sam vs Alex & Jo" — the shared caption without the competition.
    private var whoLine: String? {
        guard var tags = record.tags else { return nil }
        tags.competitionTypeRaw = nil
        return tags.displayLine
    }

    /// The full shared caption ("vs Alex · League") plus the head-to-head, so
    /// VoiceOver reads the same wording as the archive row.
    private var matchInfoAccessibilityLabel: String {
        guard let line = record.tags?.displayLine else {
            return record.matchType == .doubles ? "Add players & type" : "Add opponent & type"
        }
        return [line, headToHeadLine].compactMap { $0 }.joined(separator: ", ")
    }

    /// Completed-only head-to-head against this match's exact matchup
    /// (singles: the opponent; doubles: the pair with the same partner),
    /// excluding this match. Hidden until there is at least one result.
    private var headToHeadLine: String? {
        guard let h2h = HeadToHead.record(for: record, in: store.history), h2h.played > 0 else { return nil }
        return "Head-to-head: " + MatchComparisonFormat.headToHeadSummary(h2h)
    }
}
