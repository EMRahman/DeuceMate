// ArchiveDiagnosticsView.swift — Settings › Backup & Transfer › Archive
// Diagnostics (ARCHIVE_DERISK_PLAN.md §5). A short status, the iCloud backup
// line, collapsed file lists and the share actions. Building the report never
// changes a file; sharing stages copies in an `ExportStaging` generation that
// ends when the share sheet closes.
import SwiftUI
import UIKit
import DeuceMateCore

struct ArchiveDiagnosticsView: View {
    @ObservedObject private var store: PhoneStatsStore = .shared
    @State private var inventory: PhoneStatsStore.ArchiveInventory?
    @State private var share: StagedShare?
    /// The staged files' generation, ended when the share sheet closes.
    @State private var heldGeneration: ExportStaging.Generation?
    @State private var confirmsDamagedFiles = false
    @State private var shareError: String?

    private struct StagedShare: Identifiable {
        let generation: ExportStaging.Generation
        let urls: [URL]
        var id: UUID { generation.id }
    }

    private var report: ArchiveDiagnostics.Report? {
        inventory.map { inventory in
            ArchiveDiagnostics.Report(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                date: inventory.date,
                iCloudStatus: store.iCloudBackupStatus,
                localFiles: inventory.localFiles,
                iCloudFiles: inventory.iCloudFiles,
                damagedCopies: inventory.damagedCopies
            )
        }
    }

    var body: some View {
        List {
            if let report {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.status.title).font(.headline)
                        Text(report.status.message).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    LabeledContent("iCloud backup", value: report.iCloudStatus.text)
                }
                Section {
                    if !report.damagedCopies.isEmpty {
                        DisclosureGroup("Damaged copies (\(report.damagedCopies.count))") {
                            ForEach(report.damagedCopies, id: \.name) { copy in
                                fileRow(copy.parsed.originalFile, detail: [
                                    copy.parsed.movedAt.map { "Moved aside \($0.formatted(date: .abbreviated, time: .shortened))" }
                                        ?? "Kept by an earlier version",
                                    size(copy.size)
                                ])
                            }
                        }
                    }
                    DisclosureGroup("Files on this iPhone (\(report.localFiles.count))") {
                        ForEach(report.localFiles, id: \.name) { file in
                            fileRow(file.name, detail: [file.folder, size(file.size), modified(file.modified)]
                                + (file.isDamagedCopy ? ["Damaged copy"] : []))
                        }
                    }
                    DisclosureGroup(report.iCloudFiles.map { "Files in iCloud (\($0.count))" } ?? "Files in iCloud (unavailable)") {
                        if let files = report.iCloudFiles {
                            ForEach(files, id: \.name) { file in
                                fileRow(file.name, detail: [size(file.size), modified(file.modified), file.upload.text])
                            }
                        } else {
                            Text("iCloud is unavailable on this iPhone.").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("Share Report", systemImage: "square.and.arrow.up") { stage(report, withDamagedFiles: false) }
                    if report.status.needsAttention {
                        Button("Share Report and Damaged Files", systemImage: "doc.on.doc") { confirmsDamagedFiles = true }
                    }
                } footer: {
                    if let shareError { Text(shareError).foregroundStyle(.red) }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Archive Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let store = store
            inventory = await Task.detached { store.archiveInventory() }.value
        }
        .alert("Share Damaged Files?", isPresented: $confirmsDamagedFiles) {
            Button("Share") { if let report { stage(report, withDamagedFiles: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ArchiveDiagnostics.damagedFilesDisclosure)
        }
        .sheet(item: $share, onDismiss: endHeldShare) { share in
            GamePlanShareSheet(activityItems: share.urls) { self.share = nil }
        }
        .onDisappear(perform: endHeldShare)
    }

    private func stage(_ report: ArchiveDiagnostics.Report, withDamagedFiles: Bool) {
        let generation = ExportStaging.shared.beginGeneration()
        do {
            let reportURL = try ExportStaging.shared.write(Data(report.markdown.utf8), named: report.filename, in: generation)
            let copies = withDamagedFiles
                ? try store.copyDamagedCopies(report.attachableCopyNames, to: generation.directoryURL) : []
            shareError = nil
            endHeldShare()
            heldGeneration = generation
            share = StagedShare(generation: generation, urls: [reportURL] + copies)
        } catch {
            ExportStaging.shared.endGeneration(generation)
            shareError = "Couldn't prepare the files to share: \(error.localizedDescription)"
        }
    }

    private func endHeldShare() {
        if let heldGeneration { ExportStaging.shared.endGeneration(heldGeneration) }
        heldGeneration = nil
    }

    private func fileRow(_ name: String, detail: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.footnote.monospaced())
            Text(detail.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func size(_ bytes: Int?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Size unknown"
    }

    private func modified(_ date: Date?) -> String {
        date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Date unknown"
    }
}
