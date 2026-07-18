// main.swift — DeuceMateArchiveTool: a reusable command-line entry point for
// working with manual match archive JSON exports (see
// DeuceMateCore/Persistence/ManualMatchArchiveBackup.swift) without running the
// iOS app UI. Used to inspect an archive, render a match's interactive HTML
// web export for screenshots, and seed a simulator's app container with real
// archive data for visual QA. See docs/screenshots/README.md.
import Foundation
import DeuceMateCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    fail("""
    Usage:
      DeuceMateArchiveTool list <archive.json>
      DeuceMateArchiveTool webexport <archive.json> <index> <output.html>
      DeuceMateArchiveTool seed <archive.json> <appSupportDir> [merge|replace]
    """)
}

func loadArchive(at path: String) -> ManualMatchArchiveBackup.Archive {
    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        fail("Could not read \(path): \(error.localizedDescription)")
    }
    do {
        return try ManualMatchArchiveBackup.decode(data)
    } catch {
        fail("Could not decode archive: \(error.localizedDescription)")
    }
}

func setScoreSummary(_ record: MatchRecord) -> String {
    record.setScores.map { "\($0.gamesMe)-\($0.gamesOpponent)" }.joined(separator: ", ")
}

func durationMinutes(_ record: MatchRecord) -> String {
    guard let end = record.endTime else { return "n/a" }
    let minutes = end.timeIntervalSince(record.startTime) / 60
    return String(format: "%.1f", minutes)
}

let listDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    return formatter
}()

func runList(_ arguments: [String]) {
    guard arguments.count >= 3 else { usage() }
    let archive = loadArchive(at: arguments[2])
    for (index, record) in archive.records.enumerated() {
        let date = listDateFormatter.string(from: record.startTime)
        let won = record.iWon.map { $0 ? "W" : "L" } ?? "?"
        print("\(index) | \(record.id.uuidString) | \(date) | \(record.matchType)/\(record.matchFormat) | \(durationMinutes(record))min | sets=[\(setScoreSummary(record))] | stats=\(record.stats.count) | \(won)")
    }
}

func runWebExport(_ arguments: [String]) {
    guard arguments.count >= 5, let index = Int(arguments[3]) else { usage() }
    let outputPath = arguments[4]
    let archive = loadArchive(at: arguments[2])
    guard archive.records.indices.contains(index) else {
        fail("Index \(index) out of range (archive has \(archive.records.count) records)")
    }
    let html = MatchHTMLExporter.html(for: archive.records[index])
    do {
        try Data(html.utf8).write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("Wrote \(outputPath)")
    } catch {
        fail("Could not write HTML: \(error.localizedDescription)")
    }
}

func runSeed(_ arguments: [String]) {
    guard arguments.count >= 4 else { usage() }
    let appSupportDir = arguments[3]
    let mode: ManualMatchArchiveBackup.ImportMode = (arguments.count >= 5 && arguments[4] == "merge") ? .merge : .replace
    let archive = loadArchive(at: arguments[2])
    let snapshot = ManualMatchArchiveBackup.importSnapshot(
        importing: archive.records, into: [], tombstones: [], mode: mode
    )
    let split = HealthSidecarPolicy.split(snapshot.records)
    let archiveDir = URL(fileURLWithPath: appSupportDir).appendingPathComponent("MatchArchive", isDirectory: true)

    do {
        try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        try encoder.encode(split.stripped)
            .write(to: archiveDir.appendingPathComponent("matchHistory.json"), options: .atomic)
        try encoder.encode(Array(snapshot.tombstones))
            .write(to: archiveDir.appendingPathComponent("deletedMatchIDs.json"), options: .atomic)
        try encoder.encode(split.health)
            .write(to: archiveDir.appendingPathComponent("healthData.json"), options: .atomic)
        // Marks the initial iCloud reconcile as already done, so first launch
        // doesn't try to restore/overwrite the data we just seeded.
        try encoder.encode(true)
            .write(to: archiveDir.appendingPathComponent("archiveInitialized.json"), options: .atomic)
        print("Seeded \(snapshot.records.count) matches into \(archiveDir.path)")
    } catch {
        fail("Could not write seed files: \(error.localizedDescription)")
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { usage() }

switch arguments[1] {
case "list": runList(arguments)
case "webexport": runWebExport(arguments)
case "seed": runSeed(arguments)
default: usage()
}
