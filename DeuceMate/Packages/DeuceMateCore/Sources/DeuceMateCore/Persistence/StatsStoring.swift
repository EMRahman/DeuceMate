// StatsStoring.swift — shared persistence protocol and JSON helpers.
import Foundation

/// Persistence boundary for completed and in-progress matches. Both the watch
/// and phone targets conform with their own file-backed implementations.
public protocol StatsStoring: AnyObject {
    func loadHistory() -> [MatchRecord]
    func saveHistory(_ records: [MatchRecord])
    func appendMatch(_ record: MatchRecord)
    func removeMatch(id: UUID)
}

// MARK: - JSON codec helpers

public extension StatsStoring {
    static func decode(_ data: Data) throws -> [MatchRecord] {
        try JSONDecoder().decode([MatchRecord].self, from: data)
    }

    static func encode(_ records: [MatchRecord]) throws -> Data {
        try JSONEncoder().encode(records)
    }
}
