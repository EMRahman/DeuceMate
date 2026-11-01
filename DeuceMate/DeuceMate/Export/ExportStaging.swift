// ExportStaging.swift — where the match-detail screen stages the export
// files it shares (the interactive HTML pages), one directory per build.
//
// The detail screen rebuilds its export snapshot whenever the record or an
// export input changes (a watch checkpoint, a tag edit…). Each build is a
// GENERATION with its own directory:
//
//     <tmp>/MatchExports/<generation UUID>/deuce_mate_2026-11-01_1530.html
//
// so the user-visible filename stays the same (date only — names never reach a
// filename) while two builds can never write the same path. An older build
// that finishes after a newer one therefore cannot overwrite the newer files
// the share menu points at, and a stale report can't be shared in its place.
//
// Lifetime: the owner ends a generation (deleting its directory) when the
// build is superseded before publishing, or when a published build is
// replaced or its screen goes away. `sweepInactive()` deletes any directory no
// live generation owns — leftovers from a build whose process was killed — so
// files carrying match data (and, with PR 4, names or notes) don't linger.
import Foundation

nonisolated final class ExportStaging: @unchecked Sendable {
    static let shared = ExportStaging(
        rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("MatchExports", isDirectory: true)
    )

    /// One build's private staging directory.
    struct Generation: Hashable, Sendable {
        let id: UUID
        let directoryURL: URL

        /// Where `filename` lives in this generation. Same filename in every
        /// generation, never the same path.
        func url(for filename: String) -> URL {
            directoryURL.appendingPathComponent(filename, isDirectory: false)
        }

        /// Whether `url` is a file staged directly in this generation.
        func contains(_ url: URL) -> Bool {
            url.deletingLastPathComponent().standardizedFileURL.path == directoryURL.standardizedFileURL.path
        }
    }

    let rootURL: URL

    /// Generations begun and not yet ended in this process. Guarded by `lock`.
    private var active: Set<UUID> = []
    private let lock = NSLock()

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// Reserves a new generation. Nothing is created on disk until `write`.
    func beginGeneration(id: UUID = UUID()) -> Generation {
        lock.lock(); defer { lock.unlock() }
        active.insert(id)
        return Generation(id: id, directoryURL: rootURL.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    /// Writes `data` as `filename` inside `generation`'s directory, with the
    /// same data-at-rest protection as the canonical archive (the page carries
    /// the full record, including HealthKit-derived values).
    @discardableResult
    func write(_ data: Data, named filename: String, in generation: Generation) throws -> URL {
        try FileManager.default.createDirectory(at: generation.directoryURL, withIntermediateDirectories: true)
        let url = generation.url(for: filename)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    /// Deletes `generation`'s directory and everything in it. Idempotent.
    func endGeneration(_ generation: Generation) {
        lock.lock()
        active.remove(generation.id)
        lock.unlock()
        try? FileManager.default.removeItem(at: generation.directoryURL)
    }

    /// Deletes every directory under the root that no live generation owns.
    func sweepInactive() {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        ) else { return }
        for child in children {
            let id = UUID(uuidString: child.lastPathComponent)
            lock.lock()
            let isLive = id.map { active.contains($0) } ?? false
            lock.unlock()
            if !isLive { try? FileManager.default.removeItem(at: child) }
        }
    }

    /// Suspends until the calling task is cancelled. The detail screen's
    /// export task parks here after publishing, so SwiftUI's cancellation —
    /// a newer build replacing it, or the screen going away — is exactly when
    /// that generation's files are deleted.
    static func waitUntilCancelled() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_600_000_000_000)
        }
    }
}
