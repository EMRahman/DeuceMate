// HealthKitHRFetcher.swift — iPhone-side HealthKit reader that pulls raw
// heart-rate samples for a finished match and buckets them per point so the
// chart can show a true per-point average alongside the watch's single-snapshot
// readings.
import Combine
import Foundation
import HealthKit
import DeuceMateCore

/// Which HR series to render in a chart. Selected via a segmented control.
enum HRSeriesMode: String, CaseIterable, Identifiable {
    case snapshot
    case averaged
    case smoothed

    var id: String { rawValue }
    var label: String {
        switch self {
        case .snapshot: return String(localized: "Raw")
        case .averaged: return String(localized: "Per-point avg")
        case .smoothed: return String(localized: "Smoothed")
        }
    }
}

@MainActor
final class HealthKitHRFetcher: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([HRChartPoint])
        case unavailable
        case denied
        case empty
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let healthStore = HKHealthStore()
    private var activeTask: Task<Void, Never>?

    /// Fetches raw heart-rate samples for the match's [start, end] window and
    /// averages them per point in `filteredStats`. `firstWindowStart` is the
    /// lower bound of the first bucket — usually the timestamp of the point in
    /// `record.stats` that immediately precedes `filteredStats.first`, or
    /// `record.startTime` if there is none. Cancels any in-flight fetch so
    /// rapid set-filter changes don't race to overwrite `state` out of order.
    func load(
        for record: MatchRecord,
        filteredStats: [PointStat],
        firstWindowStart: Date
    ) {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            guard HKHealthStore.isHealthDataAvailable() else {
                self.state = .unavailable
                return
            }
            self.state = .loading

            let hrType = HKQuantityType(.heartRate)
            let readTypes: Set<HKObjectType> = [hrType]
            do {
                try await self.healthStore.requestAuthorization(toShare: [], read: readTypes)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
                return
            }
            guard !Task.isCancelled else { return }

            // HealthKit cannot distinguish "denied" from "not yet asked" on read,
            // so we proceed to query and treat an empty result as a likely-denied
            // signal only if the match actually contained snapshot HR data.
            let end = record.endTime ?? filteredStats.last?.timestamp ?? Date()
            let samples: [(Date, Double)]
            do {
                samples = try await self.fetchSamples(start: record.startTime, end: end)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
                return
            }
            guard !Task.isCancelled else { return }

            let hadSnapshots = filteredStats.contains { ($0.heartRateBPM ?? 0) > 0 }
            if samples.isEmpty {
                self.state = hadSnapshots ? .denied : .empty
                return
            }

            let bucketed = Self.bucketByPoints(
                samples: samples,
                stats: filteredStats,
                firstWindowStart: firstWindowStart
            )
            guard !Task.isCancelled else { return }
            self.state = bucketed.isEmpty ? .empty : .loaded(bucketed)
        }
    }

    private func fetchSamples(start: Date, end: Date) async throws -> [(Date, Double)] {
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, results, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let mapped: [(Date, Double)] = (results as? [HKQuantitySample] ?? []).map {
                    ($0.startDate, $0.quantity.doubleValue(for: bpmUnit))
                }
                cont.resume(returning: mapped)
            }
            healthStore.execute(q)
        }
    }

    /// Bucket sorted HR samples into one average per point. For point i the
    /// window is (prevStat.timestamp, currentStat.timestamp]; for the first
    /// point the lower bound is `firstWindowStart`. Points with no samples in
    /// their window are skipped (rather than back-filled) so the line shows
    /// real measurements only.
    static func bucketByPoints(
        samples: [(Date, Double)],
        stats: [PointStat],
        firstWindowStart: Date
    ) -> [HRChartPoint] {
        guard !samples.isEmpty, !stats.isEmpty else { return [] }
        let ordered = stats.sorted { $0.timestamp < $1.timestamp }
        var result: [HRChartPoint] = []
        result.reserveCapacity(ordered.count)
        var sampleIdx = 0
        var prevEnd = firstWindowStart
        for (i, stat) in ordered.enumerated() {
            let windowEnd = stat.timestamp
            var sum = 0.0
            var count = 0
            while sampleIdx < samples.count {
                let s = samples[sampleIdx]
                if s.0 <= prevEnd {
                    sampleIdx += 1
                    continue
                }
                if s.0 > windowEnd { break }
                sum += s.1
                count += 1
                sampleIdx += 1
            }
            if count > 0 {
                let avg = Int((sum / Double(count)).rounded())
                result.append(HRChartPoint(
                    pointIndex: i,
                    bpm: avg,
                    setIndex: stat.setIndex
                ))
            }
            prevEnd = windowEnd
        }
        return result
    }
}

/// View-private HR chart datum. Mirrors `MatchStatsSummary.HRPoint` fields the
/// chart actually reads, so the same chart code can render any of the three
/// series (raw / averaged / smoothed).
struct HRChartPoint: Equatable, Identifiable {
    let pointIndex: Int
    let bpm: Int
    let setIndex: Int
    var id: Int { pointIndex }
}
