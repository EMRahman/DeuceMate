import Foundation

/// The suggested Files location for user-confirmed manual archive exports.
nonisolated enum LocalArchiveExportDirectory {
    static func prepare(in documents: URL = .documentsDirectory) -> URL? {
        var directory = documents.appendingPathComponent("Exports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // A manual export can include HealthKit measurements and private notes.
            // Mark the app-owned directory before offering it as the default.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let applied = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            return applied.isExcludedFromBackup == true ? directory : nil
        } catch {
            // A failed suggestion leaves the normal Files picker available.
            return nil
        }
    }
}
