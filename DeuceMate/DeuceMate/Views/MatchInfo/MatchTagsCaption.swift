// MatchTagsCaption.swift — the one-line "vs Alex · League" caption shown under
// an archive row's score. Kept out of PastMatchesView (TECHNICAL_DEBT #13);
// the wording itself is Core's `MatchTags.displayLine`, shared with the watch.
// Never shows private notes.
import SwiftUI
import DeuceMateCore

struct MatchTagsCaption: View {
    let tags: MatchTags?
    let matchType: MatchType

    var body: some View {
        if let line = tags?.displayLine {
            // HStack, not Label: a Label in a List row gets the wide icon gutter.
            HStack(spacing: 4) {
                Image(systemName: matchType == .doubles ? "person.2.fill" : "person.fill")
                    .imageScale(.small)
                Text(line)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line)
            .accessibilityIdentifier("match-tags-caption")
        }
    }
}
