import Foundation

/// Archive-derived directory of players who have appeared as opponents.
public enum OpponentDirectory {
    /// Opponents only. Names are resolved from the full roster so the latest
    /// known name is retained even when that revision names the player as a partner.
    public static func entries(
        from records: [MatchRecord],
        forgotten: ForgottenPlayerLedger = ForgottenPlayerLedger()
    ) -> [RosterEntry] {
        let rosterByID = Dictionary(uniqueKeysWithValues:
            PlayerRoster.entries(from: records, forgotten: forgotten).map { ($0.id, $0) })
        var appearances: [UUID: (count: Int, lastPlayed: Date)] = [:]
        for record in records {
            guard let tags = record.tags else { continue }
            for id in Set(tags.opponents.map(\.id)) where !forgotten.contains(id) {
                if let current = appearances[id] {
                    appearances[id] = (current.count + 1, max(current.lastPlayed, MatchChronology.activityDate(record)))
                } else {
                    appearances[id] = (1, MatchChronology.activityDate(record))
                }
            }
        }
        return appearances.compactMap { id, appearance in
            guard let roster = rosterByID[id] else { return nil }
            return RosterEntry(
                id: id,
                name: roster.name,
                matchCount: appearance.count,
                lastPlayed: appearance.lastPlayed,
                handednessRaw: roster.handednessRaw,
                backhandRaw: roster.backhandRaw,
                playStyleRaw: roster.playStyleRaw
            )
        }.sorted { a, b in
            if a.lastPlayed != b.lastPlayed { return a.lastPlayed > b.lastPlayed }
            let byName = a.name.localizedCaseInsensitiveCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// Unique complete doubles identities against `playerID`, newest first.
    public static func doublesMatchups(vs playerID: UUID, in records: [MatchRecord]) -> [Matchup] {
        let matching = records.compactMap { record -> (Matchup, Date, String)? in
            guard record.matchType == .doubles,
                  let matchup = Matchup(record: record),
                  matchup.opponentIDs.contains(playerID) else { return nil }
            return (matchup, MatchChronology.date(record), record.id.uuidString)
        }.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.2 < b.2
        }
        var seen: Set<Matchup> = []
        return matching.compactMap { seen.insert($0.0).inserted ? $0.0 : nil }
    }
}
