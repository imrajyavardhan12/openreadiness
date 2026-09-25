import Foundation
import Testing
@testable import HealthInsights
@testable import ReadinessCore

enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    /// Friday 2026-09-25 09:00 UTC.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9))!

    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    static func series(_ values: [Double], endingAt offset: Int = 0) -> [DailyValue] {
        values.enumerated().map { index, value in
            DailyValue(date: day(offset - values.count + 1 + index), value: value)
        }
    }
}

@Suite struct SeriesAnalyticsTests {
    let calendar = Fixture.calendar

    @Test func bucketingAveragesDailyTotalsAndKeepsExtremes() {
        let days = (0..<14).map { i in
            DailyValue(date: Fixture.day(-13 + i), value: Double(i), min: Double(i) - 5, max: Double(i) + 5)
        }
        let weeks = SeriesAnalytics.bucketed(days, by: .weekOfYear, aggregation: .range, calendar: calendar)
        #expect(weeks.count >= 2)
        let allMins = weeks.compactMap(\.min)
        #expect(allMins.min() == -5)
        #expect(weeks.compactMap(\.max).max() == 18)
    }

    @Test func rollingMeanRequiresHalfTheWindow() {
        let values = Fixture.series([10, 20, 30])
        let rolling = SeriesAnalytics.rollingMean(values, window: 7, calendar: calendar)
        // Needs ≥ 4 of 7 days; only 3 exist.
        #expect(rolling.isEmpty)
        let longer = SeriesAnalytics.rollingMean(Fixture.series([1, 2, 3, 4, 5, 6, 7]), window: 7, calendar: calendar)
        #expect(longer.last?.value == 4)
    }

    @Test func periodComparison() throws {
        let values = Fixture.series(Array(repeating: 10.0, count: 7) + Array(repeating: 15.0, count: 7))
        let comparison = try #require(SeriesAnalytics.comparePeriods(values, days: 7, endingAt: Fixture.now, calendar: calendar))
        #expect(comparison.current == 15)
        #expect(comparison.previous == 10)
        #expect(comparison.percentChange == 50)
    }

    @Test func weekdayProfileStartsOnFirstWeekday() {
        let values = Fixture.series((0..<28).map(Double.init))
        let profile = SeriesAnalytics.weekdayProfile(values, calendar: calendar)
        #expect(profile.count == 7)
        #expect(profile.first?.weekday == 2) // Monday
        #expect(profile.allSatisfy { $0.count == 4 })
    }

    @Test func histogramUsesNiceBinsAndCountsEverything() {
        let values = (0..<100).map { Double($0) / 3 }
        let bins = SeriesAnalytics.histogram(values, targetBins: 10)
        #expect(bins.reduce(0) { $0 + $1.count } == 100)
        let width = bins[0].upper - bins[0].lower
        #expect([1.0, 2, 2.5, 5, 10].contains(width / pow(10, log10(width).rounded(.down))))
    }

    @Test func streaks() {
        // Hits on days −9…−6 (4 days), then −2…0 (3 days, current).
        let values = Fixture.series([9, 9, 9, 9, 1, 1, 1, 9, 9, 9])
        let result = SeriesAnalytics.streaks(values, today: Fixture.now, calendar: calendar) { $0 > 5 }
        #expect(result.longest?.length == 4)
        #expect(result.current?.length == 3)
    }

    @Test func trendChangeOfALine() throws {
        let values = Fixture.series((0..<10).map { Double($0) * 2 })
        #expect(abs(try #require(SeriesAnalytics.trendChange(values)) - 18) < 1e-9)
    }

    @Test func normalBandNeedsHistory() {
        let values = Fixture.series((0..<30).map { 50 + Double($0 % 5) })
        let band = SeriesAnalytics.normalBand(values, calendar: calendar)
        #expect(band.count == 30 - 7)
        #expect(band.allSatisfy { $0.low < $0.median && $0.median < $0.high })
    }
}

@Suite struct CorrelationTests {
    @Test func spearmanIsRankBasedAndHandlesTies() throws {
        let x = [1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let y = x.map { exp($0) } // monotonic but non-linear
        #expect(abs(try #require(Correlation.spearman(x, y)).rho - 1) < 1e-9)
        #expect(Correlation.ranks([10, 20, 20, 30]) == [1, 2.5, 2.5, 4])
    }

    @Test func pearsonOfPerfectNegative() {
        #expect(abs(Correlation.pearson([1, 2, 3], [3, 2, 1])! + 1) < 1e-9)
    }

    @Test func lagPairsXWithLaterY() {
        let calendar = Fixture.calendar
        let x = [Fixture.day(-2): 1.0, Fixture.day(-1): 2.0]
        let y = [Fixture.day(-1): 10.0, Fixture.day(0): 20.0]
        let pairs = Correlation.pairs(x: x, y: y, lag: 1, calendar: calendar)
        #expect(pairs.map(\.y) == [10, 20])
    }

    @Test func insightFoundForRealRelationshipButNotForNoise() {
        var rng = SplitMix64(seed: 3)
        var sleep: [Date: Double] = [:]
        var hrv: [Date: Double] = [:]
        var noise: [Date: Double] = [:]
        for i in 0..<60 {
            let day = Fixture.day(-i)
            let hours = rng.normal(mean: 7, sd: 0.8)
            sleep[day] = hours
            hrv[day] = 45 + 5 * (hours - 7) + rng.normal(mean: 0, sd: 3)
            noise[day] = rng.normal(mean: 100, sd: 10)
        }
        let insights = InsightEngine.insights(
            series: [.sleepDuration: sleep, .overnightHRV: hrv, .metric(.steps): noise],
            candidates: [InsightCandidate(.sleepDuration, .overnightHRV, lag: 0), InsightCandidate(.metric(.steps), .sleepDuration, lag: 1)],
            calendar: Fixture.calendar
        )
        #expect(insights.count == 1)
        #expect(insights.first?.x == .sleepDuration)
        #expect(insights.first?.headline == "Overnight HRV is higher after longer sleep")
        #expect((insights.first?.highMean ?? 0) > (insights.first?.lowMean ?? 0))
    }
}

@Suite struct SleepAndZonesTests {
    @Test func scheduleVariabilityAndSocialJetlag() throws {
        let calendar = Fixture.calendar
        let days = (0..<21).map { i -> DayMetrics in
            let day = Fixture.day(-i)
            let weekend = [1, 7].contains(calendar.component(.weekday, from: day))
            let start = calendar.date(byAdding: .minute, value: weekend ? 30 : -60, to: day)!
            let end = start.addingTimeInterval(7.5 * 3600)
            let sleep = SleepSummary(start: start, end: end, asleep: 7 * 3600, awake: 1800, deep: 0, rem: 0, core: 0, unspecified: 7 * 3600, interruptions: 0, segments: [])
            return DayMetrics(day: day, sleep: sleep)
        }
        let analysis = try #require(SleepScheduleAnalysis.analyze(days, calendar: calendar))
        #expect(analysis.medianStart == -60)
        #expect(abs(try #require(analysis.socialJetlag) - 90) < 1e-9)
    }

    @Test func karvonenZones() {
        let zones = HeartRateZones(resting: 60, maximum: 180)
        #expect(zones.lowerBounds == [120, 132, 144, 156, 168])
        #expect(zones.zone(for: 100) == 0)
        #expect(zones.zone(for: 150) == 2)
        #expect(zones.zone(for: 175) == 4)
    }

    @Test func timeInZonesCapsGaps() {
        let zones = HeartRateZones(resting: 60, maximum: 180)
        let t0 = Fixture.now
        let samples = [TimedValue(date: t0, value: 150), TimedValue(date: t0.addingTimeInterval(10), value: 170)]
        let totals = zones.timeInZones(samples, until: t0.addingTimeInterval(1000))
        #expect(totals[2] == 10)
        #expect(totals[4] == 60) // gap capped
    }
}

@Suite struct DemoProviderTests {
    @Test func everyMetricHasDataAndMatchesTheReadinessDemo() async throws {
        let provider = DemoMetricsProvider(calendar: Fixture.calendar, now: Fixture.now)
        let year = DateInterval(start: Fixture.day(-365), end: Fixture.now)
        for metric in HealthMetric.allCases {
            let values = try await provider.daily(metric, in: year)
            #expect(!values.isEmpty, "\(metric)")
        }
        // Same HRV for the same day regardless of the requested window.
        let short = DemoDataSource(seed: 42, calendar: Fixture.calendar).generate(from: Fixture.day(-30), to: Fixture.now)
        let long = DemoDataSource(seed: 42, calendar: Fixture.calendar).generate(from: Fixture.day(-300), to: Fixture.now)
        let cutoff = Fixture.day(-20)
        let a = short.hrv.filter { $0.date >= cutoff }
        let b = long.hrv.filter { $0.date >= cutoff }
        #expect(a.count == b.count)
        #expect(zip(a, b).allSatisfy { $0.date == $1.date && abs($0.value - $1.value) < 0.01 })
    }

    @Test func intradayAndWorkouts() async throws {
        let provider = DemoMetricsProvider(calendar: Fixture.calendar, now: Fixture.now)
        let day = try await provider.intraday(on: Fixture.day(-2))
        #expect(day.heartRate.count == 288)
        #expect(day.hourlySteps.count == 24)
        let workouts = try await provider.workouts(in: DateInterval(start: Fixture.day(-14), end: Fixture.now))
        #expect(!workouts.isEmpty)
        let first = try #require(workouts.first)
        let samples = try await provider.heartRateSamples(in: DateInterval(start: first.start, end: first.end))
        #expect(samples.count > 100)
    }
}
