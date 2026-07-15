// BackupExcludedFileWriter.swift — atomic Class B writes excluded from device backup.
import Foundation

enum BackupExcludedFileWriter {
    enum WriteError: LocalizedError {
        case exclusionNotApplied(URL)

        var errorDescription: String? {
            switch self {
            case .exclusionNotApplied(let url):
                return "Backup exclusion was not applied to \(url.lastPathComponent)."
            }
        }
    }

    static func write<T: Encodable>(_ value: T, to originalURL: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(
            to: originalURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try excludeFromBackup(at: originalURL)
    }

    static func excludeFromBackup(at originalURL: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = originalURL
        try url.setResourceValues(values)
        guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true else {
            throw WriteError.exclusionNotApplied(originalURL)
        }
    }
}
