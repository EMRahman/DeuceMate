// ArchiveExportFlow.swift — the single manual archive export flow shared by
// Settings › Backup & Transfer and the Matches-screen export reminder card
// (docs/features/ARCHIVE_EXPORT_REMINDER_PLAN.md §5.2).
//
// Owns presenting `ArchiveExportOptionsSheet`, encoding the archive off-main,
// presenting `fileExporter`, and recording success on
// `ArchiveExportReminderCoordinator`. Both surfaces behave identically and
// there is only one place that records a successful export.
import SwiftUI
import UniformTypeIdentifiers
import DeuceMateCore

struct MatchArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ArchiveTransferStatus: Equatable {
    let message: String
    let isSuccess: Bool
}

enum ArchiveExportOutcome: Equatable {
    case exported
    case failed(String)
    case cancelled
}

private struct ArchiveExportFlowModifier: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject var store: PhoneStatsStore
    var notesStore: MatchNotesStore
    var reminderCoordinator: ArchiveExportReminderCoordinator
    var onOutcome: (ArchiveExportOutcome) -> Void

    @State private var showFileExporter = false
    @State private var document = MatchArchiveDocument()

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                // The disclosure plus the separate, default-off private-notes
                // opt-in with an exact preview. Built when the sheet is up only.
                ArchiveExportOptionsSheet(
                    baseMessage: archiveExportDisclosureMessage,
                    notes: archiveExportNoteLines,
                    clearedCount: archiveExportNoteEntries.filter(\.isCleared).count,
                    onExport: { includeNotes in
                        isPresented = false
                        prepareManualArchiveExport(includeNotes: includeNotes)
                    },
                    onCancel: {
                        isPresented = false
                        onOutcome(.cancelled)
                    }
                )
            }
            // Deliberately leave `fileDialogDefaultDirectory` unset: sandboxed
            // iOS apps cannot target the Files app's user Downloads folder, and
            // leaving it unset lets iOS remember the last folder the user chose.
            // On cancel, SwiftUI dismisses without calling `onCompletion` (or
            // passes NSUserCancelledError); either way nothing is recorded.
            .fileExporter(
                isPresented: $showFileExporter,
                document: document,
                contentType: .json,
                defaultFilename: manualArchiveFilename
            ) { result in
                switch result {
                case .success:
                    reminderCoordinator.recordExport()
                    onOutcome(.exported)
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                        onOutcome(.cancelled)
                    } else {
                        onOutcome(.failed(error.localizedDescription))
                    }
                }
            }
    }

    private var manualArchiveFilename: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return "deucemate_archive_\(formatter.string(from: Date())).json"
    }

    /// The archive-export disclosure body. When any archived match carries
    /// HealthKit data, use Core's single disclosure source (naming exactly the
    /// raw fields present, `.archiveFile` recipient); otherwise a health-free
    /// export note.
    private var archiveExportDisclosureMessage: String {
        let fields = HealthExportConsent.archiveFields(in: store.history)
        guard !fields.isEmpty else {
            return "Export your full match archive as a JSON file. Choose where to save it in the Files app or an iCloud Drive folder."
        }
        return HealthExportConsent.disclosure(fields: fields, destination: .archiveFile).message
    }

    /// Every note entry (including explicit clears) on a match in the archive —
    /// exactly what "Include private notes" would write.
    private var archiveExportNoteEntries: [MatchNote] {
        ManualMatchArchiveBackup.exportableNotes(notesStore.allNotes(), for: store.history)
    }

    /// The non-empty entries, newest match first, for the exact-text preview.
    private var archiveExportNoteLines: [ArchiveExportOptionsSheet.NoteLine] {
        let notes = Dictionary(
            archiveExportNoteEntries.filter { !$0.isCleared }.map { ($0.matchID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return store.history.compactMap { record in
            notes[record.id].map { ArchiveExportOptionsSheet.NoteLine(note: $0, matchDate: MatchChronology.date(record)) }
        }
    }

    private func prepareManualArchiveExport(includeNotes: Bool) {
        let store = store
        // Resolved here (main actor) so the exact set the user reviewed is the
        // set written, even if a note changes while the file is prepared.
        let notes = includeNotes ? archiveExportNoteEntries : nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try store.exportManualArchiveData(notes: notes)
                DispatchQueue.main.async {
                    document = MatchArchiveDocument(data: data)
                    showFileExporter = true
                }
            } catch {
                DispatchQueue.main.async {
                    onOutcome(.failed(error.localizedDescription))
                }
            }
        }
    }
}

extension View {
    @MainActor
    func archiveExportFlow(
        isPresented: Binding<Bool>,
        store: PhoneStatsStore,
        notesStore: MatchNotesStore = .shared,
        reminderCoordinator: ArchiveExportReminderCoordinator,
        onOutcome: @escaping (ArchiveExportOutcome) -> Void
    ) -> some View {
        modifier(
            ArchiveExportFlowModifier(
                isPresented: isPresented,
                store: store,
                notesStore: notesStore,
                reminderCoordinator: reminderCoordinator,
                onOutcome: onOutcome
            )
        )
    }
}
