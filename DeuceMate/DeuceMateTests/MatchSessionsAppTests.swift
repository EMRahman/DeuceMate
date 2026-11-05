import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

@MainActor
struct MatchSessionsAppTests {
    private func fixture(knownPark: Bool = true) -> MatchRecord {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [10.0,20,100010,100020].enumerated().map { index, seconds in
            PointStat(timestamp: start.addingTimeInterval(seconds), setIndex: index < 2 ? 0 : 1,
                      server: .me, winner: .me, outcome: .winner, heartRateBPM: 130,
                      stepsCumulative: [100,110,200,206][index])
        }
        return MatchRecord(startTime: start, endTime: start.addingTimeInterval(100030),
            setScores: [SetScore(),SetScore()], stats: points, matchElapsedSeconds: 600,
            resumeEvents: [MatchResumeEvent(resumedAt: start.addingTimeInterval(100000),
                pausedAt: knownPark ? start.addingTimeInterval(30) : nil, precedingPointID: points[1].id)])
    }

    @Test func sessionBucketingExcludesParkGapAndRetainsFullCoordinatesForSetFilter() {
        let record = fixture()
        let start = record.startTime
        let samples: [(Date, Double)] = [(start.addingTimeInterval(15),140),
            (start.addingTimeInterval(50000),220), (start.addingTimeInterval(100005),150),
            (start.addingTimeInterval(100015),160)]
        let secondSet = Array(record.stats.suffix(2))
        let buckets = HealthKitHRFetcher.bucketBySession(samples: samples, record: record, filteredStats: secondSet)
        #expect(buckets.map(\.pointIndex) == [0,1])
        #expect(buckets.map(\.bpm) == [150,160])
        let full = HealthKitHRFetcher.bucketBySession(samples: samples, record: record, filteredStats: record.stats)
        #expect(full.map(\.pointIndex) == [1,2,3])
        #expect(full.map(\.bpm) == [140,150,160])
    }

    @Test func unknownParkClockReversalAndRepeatedBoundaryFallBackSafely() {
        var record = fixture(knownPark: false)
        let start = record.startTime
        let samples: [(Date, Double)] = [(start.addingTimeInterval(15),220), (start.addingTimeInterval(100005),150)]
        let first = HealthKitHRFetcher.bucketBySession(samples: samples, record: record, filteredStats: record.stats)
        #expect(first.map(\.bpm) == [130,130,150])
        record.resumeEvents.append(MatchResumeEvent(resumedAt: start.addingTimeInterval(99999),
            pausedAt: start.addingTimeInterval(99998), precedingPointID: record.stats[1].id))
        #expect(HealthKitHRFetcher.bucketBySession(samples: samples, record: record, filteredStats: Array(record.stats.suffix(2))).first?.bpm == 150)
        record.resumeEvents = [MatchResumeEvent(resumedAt: start.addingTimeInterval(100000),
            pausedAt: start.addingTimeInterval(100001), precedingPointID: record.stats[1].id)]
        #expect(HealthKitHRFetcher.bucketBySession(samples: samples, record: record, filteredStats: Array(record.stats.prefix(2))).map(\.bpm) == [130,130])
    }

    @Test func allTextAndAIPerspectivesCarrySessionContextAndResetRawStepLoad() {
        let record = fixture(knownPark: false)
        for focal in [Player.me,.opponent] {
            let summary = MatchExporter.summaryExport(for: record, focal: focal)
            let full = MatchExporter.fullExport(for: record, focal: focal)
            let ai = MatchExporter.aiPromptExport(for: record, focal: focal)
            for output in [summary,full,ai] {
                #expect(output.contains("## Play sessions"))
                #expect(output.contains("Break duration unknown"))
                #expect(output.contains("Recorded play time"))
                #expect(output.contains("do not establish fatigue or recovery"))
            }
            #expect(full.contains("| 0 | 200 |"))
            #expect(!full.contains("| 90 | 200 |"))
        }
    }
}
