// ArchiveDiagnostics.swift — Archive Diagnostics (ARCHIVE_DERISK_PLAN.md §5):
// the dated damaged-copy names the iPhone store writes, the screen's status
// wording, and a Markdown report a person or a coding agent can act on.
//
// Pure: `PhoneStatsStore` lists the files and reads the damaged copies' bytes;
// nothing here touches disk. The report never contains a match, a name or a
// note: it holds file metadata, hashes, decoding errors (a coding path and the
// rejected value) and fixed text.
import Foundation
import CryptoKit

public enum ArchiveDiagnostics {

    // MARK: - Damaged-copy names

    /// The canonical files iCloud backs up. A damaged copy of one pauses iCloud.
    public static let backedUpFiles = ["matchHistory.json", "deletedMatchIDs.json", "forgottenPlayers.json"]
    /// The Health sidecar: reported, never attached, never pauses (§3.2, §5.2).
    public static let healthFile = "healthData.json"
    public static let supportAddress = "mail@ehsanrahman.com"

    /// `<file>.corrupt-<yyyyMMdd'T'HHmmss>` in UTC (§3.1). 1.4.0 used an undated
    /// `<file>.corrupt`, which `parseDamagedCopy` still recognises.
    public static func damagedCopyName(for file: String, at date: Date) -> String {
        file + ".corrupt-" + ISO8601DateFormatter.string(from: date, timeZone: utc, formatOptions: stampOptions)
    }

    public struct DamagedCopyName: Equatable, Sendable {
        public let originalFile: String
        /// False for 1.4.0's undated copy, which never pauses iCloud.
        public let isDated: Bool
        /// When it was moved aside; nil for an undated copy.
        public let movedAt: Date?
        public var isBackedUpFile: Bool { ArchiveDiagnostics.backedUpFiles.contains(originalFile) }
    }

    /// nil when `name` isn't a damaged copy of a file the store keeps.
    public static func parseDamagedCopy(_ name: String) -> DamagedCopyName? {
        for file in backedUpFiles + [healthFile] {
            if name == file + ".corrupt" { return DamagedCopyName(originalFile: file, isDated: false, movedAt: nil) }
            guard name.hasPrefix(file + ".corrupt-") else { continue }
            let stamp = String(name.dropFirst(file.count + ".corrupt-".count))
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = utc
            formatter.formatOptions = stampOptions
            return DamagedCopyName(originalFile: file, isDated: true, movedAt: formatter.date(from: stamp))
        }
        return nil
    }

    // MARK: - Status

    public enum Status: Equatable, Sendable {
        case noProblems, damaged, legacyOnly

        public var needsAttention: Bool { self != .noProblems }
        /// Only a dated copy of a backed-up file pauses iCloud (§3.2).
        public var pausesICloud: Bool { self == .damaged }

        public var title: String {
            switch self {
            case .noProblems: return "No problems found"
            case .damaged:    return "Some match data couldn't be opened"
            case .legacyOnly: return "An earlier version couldn't open some match data"
            }
        }

        public var message: String {
            switch self {
            case .noProblems:
                return "Your match archive opened normally. If support asks for diagnostics, share the report below."
            case .damaged:
                return "DeuceMate kept a copy of the file it couldn't read. Nothing has been deleted. Your iCloud backup is paused, so it still holds your matches as they were. It resumes by itself once an app update recovers the copy.\n\nThis usually means an app update is needed. Check the App Store. If there isn't one, share the report below with DeuceMate support, or give it to a coding agent to look at."
            case .legacyOnly:
                return "DeuceMate kept a copy of the file. Your iCloud backup wasn't paused at the time and may have been replaced, so this copy may be the only one of those matches. Keep it, and share the report below with DeuceMate support."
            }
        }
    }

    /// The status for the names in `MatchArchive/`. Health sidecar copies don't count.
    public static func status(forArchiveFileNames names: [String]) -> Status {
        let copies = names.compactMap(parseDamagedCopy).filter(\.isBackedUpFile)
        if copies.contains(where: \.isDated) { return .damaged }
        return copies.isEmpty ? .noProblems : .legacyOnly
    }

    public static let damagedFilesDisclosure = "These files contain your scores, player names and playing style notes. Files from older versions may also contain heart rate, steps, distance and calories. Private match notes are never included. Only share them with DeuceMate support or a tool you trust. Never post them publicly."

    // MARK: - Files

    public struct LocalFile: Equatable, Sendable {
        public let folder: String
        public let name: String
        public let size: Int?
        public let modified: Date?
        public init(folder: String, name: String, size: Int?, modified: Date?) {
            self.folder = folder; self.name = name; self.size = size; self.modified = modified
        }
        public var isDamagedCopy: Bool { folder == "MatchArchive" && parseDamagedCopy(name) != nil }
    }

    public struct ICloudFile: Equatable, Sendable {
        public let name: String
        public let size: Int?
        public let modified: Date?
        public let upload: UploadStatus
        public let isDownloaded: Bool?
        public init(name: String, size: Int?, modified: Date?, upload: UploadStatus, isDownloaded: Bool?) {
            self.name = name; self.size = size; self.modified = modified; self.upload = upload; self.isDownloaded = isDownloaded
        }

        /// A not-downloaded placeholder (`.<name>.icloud` on older iOS) is shown under its real name.
        public static func displayName(forEntry entry: String) -> String {
            guard entry.hasPrefix("."), entry.hasSuffix(".icloud"), entry.count > ".icloud".count + 1 else { return entry }
            return String(entry.dropFirst().dropLast(".icloud".count))
        }
    }

    public enum UploadStatus: Equatable, Sendable {
        case uploaded, uploading, waiting, failed(domain: String, code: Int), unknown

        public init(isUploaded: Bool?, isUploading: Bool?, errorDomain: String?, errorCode: Int?) {
            if let errorDomain, let errorCode { self = .failed(domain: errorDomain, code: errorCode) }
            else if isUploaded == true { self = .uploaded }
            else if isUploading == true { self = .uploading }
            else if isUploaded == false { self = .waiting }
            else { self = .unknown }
        }

        public var text: String {
            switch self {
            case .uploaded: return "Uploaded"
            case .uploading: return "Uploading"
            case .waiting: return "Waiting to upload"
            case let .failed(domain, code): return "Upload failed (\(domain) \(code))"
            case .unknown: return "unknown"
            }
        }
    }

    // MARK: - Damaged copies

    public struct DamagedCopy: Equatable, Sendable {
        public let name: String
        public let parsed: DamagedCopyName
        public let size: Int?
        public let sha256: String?
        public let decode: DecodeResult

        /// `data` nil = the copy couldn't be read.
        public init?(name: String, data: Data?) {
            guard let parsed = parseDamagedCopy(name) else { return nil }
            self.name = name
            self.parsed = parsed
            size = data?.count
            sha256 = data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
            decode = data.map { decodeResult(of: $0, asContentsOf: parsed.originalFile) } ?? .unreadable
        }
    }

    public enum DecodeResult: Equatable, Sendable {
        case readable
        case unreadable
        case failed(errorType: String, codingPath: String, detail: String)
    }

    /// Decodes the copy again with this build, as the store reads that file.
    public static func decodeResult(of data: Data, asContentsOf file: String) -> DecodeResult {
        let decoder = JSONDecoder()
        do {
            switch file {
            case "matchHistory.json":     _ = try decoder.decode([MatchRecord].self, from: data)
            case "deletedMatchIDs.json":  _ = try decoder.decode([UUID].self, from: data)
            case "forgottenPlayers.json": _ = try decoder.decode(ForgottenPlayerLedger.self, from: data)
            default:                      _ = try decoder.decode([MatchHealthData].self, from: data)
            }
            return .readable
        } catch let DecodingError.typeMismatch(_, context) {
            return failure("typeMismatch", context.codingPath, context)
        } catch let DecodingError.valueNotFound(_, context) {
            return failure("valueNotFound", context.codingPath, context)
        } catch let DecodingError.keyNotFound(key, context) {
            return failure("keyNotFound", context.codingPath + [key], context)
        } catch let DecodingError.dataCorrupted(context) {
            return failure("dataCorrupted", context.codingPath, context)
        } catch {
            let nsError = error as NSError
            return .failed(errorType: nsError.domain, codingPath: "", detail: "code \(nsError.code)")
        }
    }

    private static func failure(_ type: String, _ path: [CodingKey], _ context: DecodingError.Context) -> DecodeResult {
        .failed(errorType: type, codingPath: readablePath(path), detail: context.debugDescription)
    }

    /// `[12].stats[204].endingShot`
    public static func readablePath(_ path: [CodingKey]) -> String {
        path.reduce(into: "") { text, key in
            if let index = key.intValue { text += "[\(index)]" }
            else { text += text.isEmpty ? key.stringValue : ".\(key.stringValue)" }
        }
    }

    // MARK: - Report

    public struct Report: Equatable, Sendable {
        public var appVersion: String
        public var appBuild: String
        public var osVersion: String
        public var date: Date
        public var iCloudStatus: ICloudBackupCopy
        public var localFiles: [LocalFile]
        /// nil = iCloud unavailable, so its files can't be listed.
        public var iCloudFiles: [ICloudFile]?
        public var damagedCopies: [DamagedCopy]

        public init(
            appVersion: String, appBuild: String, osVersion: String, date: Date,
            iCloudStatus: ICloudBackupCopy, localFiles: [LocalFile], iCloudFiles: [ICloudFile]?,
            damagedCopies: [DamagedCopy]
        ) {
            self.appVersion = appVersion; self.appBuild = appBuild; self.osVersion = osVersion; self.date = date
            self.iCloudStatus = iCloudStatus; self.localFiles = localFiles; self.iCloudFiles = iCloudFiles
            self.damagedCopies = damagedCopies
        }

        public var status: Status { ArchiveDiagnostics.status(forArchiveFileNames: damagedCopies.map(\.name)) }

        /// Damaged copies of the backed-up files. The Health sidecar's is never attached.
        public var attachableCopyNames: [String] { damagedCopies.filter(\.parsed.isBackedUpFile).map(\.name) }

        public var filename: String {
            "DeuceMate-archive-report-\(ISO8601DateFormatter.string(from: date, timeZone: utc, formatOptions: [.withFullDate])).md"
        }

        public var markdown: String {
            var lines = ["# DeuceMate archive report", "", "## 1. What happened", ""]
            switch status {
            case .noProblems: lines.append("No damaged copies of match data. The match archive opened normally.")
            case .damaged: lines.append("This iPhone couldn't decode a match archive file and kept it as a dated copy (section 4). iCloud backup is paused, so the iCloud copy still holds the matches as they were.")
            case .legacyOnly: lines.append("An earlier version couldn't decode a match archive file and kept an undated copy (section 4). iCloud backup wasn't paused then, so this copy may be the only one of those matches.")
            }
            lines += ["", "Support: \(supportAddress)", "", "## 2. Environment", "",
                      "- App: \(appVersion) (build \(appBuild))", "- OS: \(osVersion)", "- Report date: \(iso(date))",
                      "", "## 3. Files", "", "### On this iPhone", "",
                      "| Folder | Name | Size (bytes) | Modified | Damaged copy |", "|---|---|---|---|---|"]
            lines += localFiles.map { "| \($0.folder) | \($0.name) | \(text($0.size)) | \(iso($0.modified)) | \($0.isDamagedCopy ? "yes" : "no") |" }
            lines += ["", "### In iCloud", "", "iCloud backup: \(iCloudStatus.text)", ""]
            if let iCloudFiles {
                lines += ["| Name | Size (bytes) | Modified | Upload | Downloaded |", "|---|---|---|---|---|"]
                lines += iCloudFiles.map { "| \($0.name) | \(text($0.size)) | \(iso($0.modified)) | \($0.upload.text) | \($0.isDownloaded.map { $0 ? "yes" : "no" } ?? "unknown") |" }
            } else {
                lines.append("iCloud is unavailable on this iPhone, so its files can't be listed.")
            }
            if !damagedCopies.isEmpty {
                lines += ["", "## 4. Damaged copies"]
                for copy in damagedCopies {
                    lines += ["", "### \(copy.name)", "", "- Original file: \(copy.parsed.originalFile)",
                              "- Moved aside: \(copy.parsed.isDated ? iso(copy.parsed.movedAt) : "unknown (kept by an earlier version)")",
                              "- Size: \(text(copy.size)) bytes", "- SHA-256: \(copy.sha256 ?? "unknown")"]
                    switch copy.decode {
                    case .readable: lines.append("- Decoding it now: **this build can read this file.**")
                    case .unreadable: lines.append("- Decoding it now: the copy couldn't be read.")
                    case let .failed(type, path, detail):
                        lines.append("- Decoding it now: fails. `\(type)` at `\(path.isEmpty ? "(top level)" : path)`: \(detail)")
                    }
                }
            }
            lines += ["", "## 5. Stored values this build accepts", ""] + acceptedValues
            if status.needsAttention { lines += ["", "## 6. Instructions for a coding agent", ""] + agentInstructions }
            return lines.joined(separator: "\n") + "\n"
        }

        private func iso(_ date: Date?) -> String { date.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown" }
        private func text(_ value: Int?) -> String { value.map(String.init) ?? "unknown" }
    }

    static let acceptedValues: [String] = [
        "- MatchFormat: " + MatchFormat.allCases.map(\.rawValue).joined(separator: ", "),
        "- MatchType: " + MatchType.allCases.map(\.rawValue).joined(separator: ", "),
        "- Player: " + Player.allCases.map(\.rawValue).joined(separator: ", "),
        "- DoublesServer: " + DoublesServer.allCases.map(\.rawValue).joined(separator: ", "),
        "- PointOutcome: " + PointOutcome.allCases.map(\.rawValue).joined(separator: ", "),
        "- EndingShot: " + EndingShot.allCases.map(\.rawValue).joined(separator: ", ")
    ]

    static let agentInstructions: [String] = [
        "- Never change or delete the original file. Work on a copy.",
        "- **Change values, never drop records.** If the bad value looks like one DeuceMate used to accept (for example an old format name), stop. It's an app bug, and an update will read it unchanged. Tell the user to contact support.",
        "- To return a repaired archive, wrap the repaired `matchHistory.json` array in a manual archive file: `{\"format\": \"deucemate.matchArchive\", \"schemaVersion\": 1, \"exportedAt\": <seconds since 2001-01-01, or an ISO-8601 string>, \"includesHealthData\": <true if any record has Health fields>, \"records\": [...]}`. Dates in the records are already in the right encoding, so copy them as they are.",
        "- If `forgottenPlayers.json` was attached, copy its object into a `forgottenPlayers` key.",
        "- Then the user imports it with Settings › Backup & Transfer › Import Match Archive › **Merge**.",
        "- This report doesn't contain the file. Ask the user for the damaged files if they weren't attached."
    ]

    private static let utc = TimeZone(identifier: "UTC") ?? .current
    private static let stampOptions: ISO8601DateFormatter.Options = [.withYear, .withMonth, .withDay, .withTime]
}
