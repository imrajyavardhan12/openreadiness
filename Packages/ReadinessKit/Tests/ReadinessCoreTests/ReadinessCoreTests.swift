import Foundation
import Testing
@testable import ReadinessCore

/// Fixed calendar and "now" so tests don't depend on the machine's locale or clock.
enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-09-25 09:00 UTC.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9))!

    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    static func time(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: calendar.startOfDay(for: now))!
    }

    static func demo(illnessDaysAgo: Int = 21) -> RawHealthData {
        DemoDataSource(seed: 7, calendar: calendar, illnessDaysAgo: illnessDaysAgo)
            .generate(from: day(-200), to: now)
    }
}

// MARK: - Statistics

@Suite struct StatsTests {
    @Test func medianAndMAD() {
        #expect(Stats.median([3, 1, 2]) == 2)
        #expect(Stats.median([4, 1, 3, 2]) == 2.5)
        #expect(Stats.median([]) == nil)
        #expect(Stats.mad([1, 2, 3, 4, 100]) == 1)
    }

    @Test func geometricMeanIgnoresNonPositive() {
        #expect(abs(Stats.geometricMean([10, 1000, 0])! - 100) < 1e-9)
    }

    @Test func subscoreIsCalibratedAndMonotonic() {
        #expect(abs(Stats.subscore(fromZ: 0) - 70) < 0.1)
        let zs = stride(from: -4.0, through: 4.0, by: 0.5).map(Stats.subscore(fromZ:))
        #expect(zs == zs.sorted())
        #expect(zs.first! > 0 && zs.last! < 100)
    }

    @Test func robustBaselineRequiresMinimumCountAndFloorsSpread() {
        #expect(Baseline.robust([1, 2, 3], minimumCount: 7, minimumSpread: 1) == nil)
        let flat = Baseline.robust(Array(repeating: 50, count: 10), minimumCount: 7, minimumSpread: 1.5)!
        #expect(flat.median == 50)
        #expect(flat.spread == 1.5)
    }
}

// MARK: - Sleep

@Suite struct SleepAnalyzerTests {
    let analyzer = SleepAnalyzer(calendar: Fixture.calendar)

    @Test func usesSingleBestSourceInsteadOfDoubleCounting() {
        let watch = [
            SleepSegment(start: Fixture.time(-1, 23), end: Fixture.time(0, 3), stage: .core, sourceID: "watch"),
            SleepSegment(start: Fixture.time(0, 3), end: Fixture.time(0, 3, 10), stage: .awake, sourceID: "watch"),
            SleepSegment(start: Fixture.time(0, 3, 10), end: Fixture.time(0, 4), stage: .deep, sourceID: "watch"),
            SleepSegment(start: Fixture.time(0, 4), end: Fixture.time(0, 7), stage: .rem, sourceID: "watch"),
        ]
        // A phone app claiming the same night, unstaged.
        let phone = [SleepSegment(start: Fixture.time(-1, 22), end: Fixture.time(0, 7), stage: .asleepUnspecified, sourceID: "phone")]

        let summary = analyzer.summarize(watch + phone, wakeDay: Fixture.day(0))!
        #expect(summary.asleep == 7 * 3600 + 50 * 60)
        #expect(summary.awake == 10 * 60)
        #expect(summary.interruptions == 1)
        #expect(summary.deep == 50 * 60)
        #expect(summary.rem == 3 * 3600)
        #expect(summary.unspecified == 0)
    }

    @Test func afternoonNapIsNotTheMainSleep() {
        let nap = [SleepSegment(start: Fixture.time(0, 16), end: Fixture.time(0, 17), stage: .core, sourceID: "watch")]
        #expect(analyzer.summarize(nap, wakeDay: Fixture.day(0)) == nil)
    }

    @Test func tinyGapsAreNotInterruptions() {
        let segments = [
            SleepSegment(start: Fixture.time(-1, 23), end: Fixture.time(0, 2), stage: .core, sourceID: "w"),
            SleepSegment(start: Fixture.time(0, 2, 1), end: Fixture.time(0, 6), stage: .core, sourceID: "w"),
        ]
        #expect(analyzer.summarize(segments, wakeDay: Fixture.day(0))?.interruptions == 0)
    }
}

// MARK: - Training load

@Suite struct WorkoutLoadTests {
    let model = WorkoutLoadModel(restingHeartRate: 60, maxHeartRate: 180)

    func workout(effort: Double? = nil, estimated: Bool = false, hr: Double? = nil, kcal: Double? = nil) -> WorkoutRecord {
        WorkoutRecord(
            start: Fixture.time(0, 7), end: Fixture.time(0, 8), activityName: "Run",
            activeEnergyKcal: kcal, averageHeartRate: hr, effortScore: effort, effortIsEstimated: estimated
        )
    }

    @Test func effortSourcePriority() {
        #expect(model.score(workout(effort: 7, hr: 150)).effortSource == .userRated)
        #expect(model.score(workout(effort: 5, estimated: true)).effortSource == .appleEstimated)
        #expect(model.score(workout(hr: 150)).effortSource == .heartRate)
        #expect(model.score(workout(kcal: 600)).effortSource == .energy)
        #expect(model.score(workout()).effortSource == .assumed)
    }

    @Test func sessionRPEisMinutesTimesEffort() {
        #expect(model.score(workout(effort: 7)).load == 420)
        // (150 − 60) / (180 − 60) = 0.75 → effort 7.5
        #expect(abs(model.score(workout(hr: 150)).effort - 7.5) < 1e-9)
    }

    @Test func ratioSubscoreDecreasesWithSpikes() {
        let scores = [0.5, 0.9, 1.2, 1.4, 1.7, 2.5].map(TrainingLoadScorer.ratioSubscore)
        #expect(scores == scores.sorted(by: >))
    }

    @Test func tanakaMaxHeartRate() {
        #expect(WorkoutLoadModel.predictedMaxHeartRate(age: 40) == 180)
    }
}

// MARK: - Engine

@Suite struct ReadinessEngineTests {
    let engine = ReadinessEngine(calendar: Fixture.calendar)

    @Test func categoriesMatchApplesBands() {
        #expect((0...10).map { ReadinessCategory(score: $0) } == [
            .recover, .recover, .paceYourself, .paceYourself, .paceYourself,
            .ready, .ready, .ready, .goForIt, .goForIt, .goForIt,
        ])
    }

    @Test func scoresTodayFromDemoData() throws {
        let analysis = engine.analyze(Fixture.demo(), now: Fixture.now)
        let today = try #require(analysis.today)
        #expect((0...10).contains(today.score))
        #expect(!today.isCalibrating)
        #expect(Set(today.contributors.map(\.kind)) == Set(ContributorKind.allCases))
        let weightSum = today.contributors.reduce(0) { $0 + $1.effectiveWeight }
        #expect(abs(weightSum - 1) < 1e-9)
        #expect(!today.summary.isEmpty)
    }

    /// Design intent: an ordinary day for *you* is a 7 ("Ready"), not an 8.
    @Test func typicalDayIsReady() {
        for seed: UInt64 in [7, 42, 99] {
            let raw = DemoDataSource(seed: seed, calendar: Fixture.calendar).generate(from: Fixture.day(-200), to: Fixture.now)
            let scores = engine.analyze(raw, now: Fixture.now).orderedScores.map(\.score)
            #expect(Stats.median(scores.map(Double.init)) == 7, "seed \(seed)")
        }
    }

    @Test func isDeterministic() {
        let a = engine.analyze(Fixture.demo(), now: Fixture.now)
        let b = engine.analyze(Fixture.demo(), now: Fixture.now)
        #expect(a.orderedScores == b.orderedScores)
    }

    @Test func illnessLowersTheScoreAndFlagsVitals() throws {
        let analysis = engine.analyze(Fixture.demo(illnessDaysAgo: 30), now: Fixture.now)
        let sick = try #require(analysis.scores[Fixture.day(-28)])
        let healthy = try #require(analysis.scores[Fixture.day(-40)])
        #expect(sick.score < healthy.score)
        #expect(sick.score <= 4)
        #expect(try #require(sick.contributor(.vitals)).status <= .caution)
    }

    @Test func calibratesWithTooLittleHistory() {
        let raw = DemoDataSource(seed: 1, calendar: Fixture.calendar).generate(from: Fixture.day(-3), to: Fixture.now)
        let analysis = engine.analyze(raw, now: Fixture.now)
        if let today = analysis.today {
            #expect(today.isCalibrating)
            #expect(today.contributor(.hrv) == nil)
        }
    }

    @Test func noDataMeansNoScore() {
        #expect(engine.analyze(RawHealthData(), now: Fixture.now).today == nil)
    }

    func contributor(_ kind: ContributorKind, _ subscore: Double, weight: Double) -> Contributor {
        Contributor(kind: kind, subscore: subscore, weight: weight, value: nil, normalRange: nil, headline: "", summaryPhrase: "", components: [])
    }

    @Test func limitingFactorCapsTheScore() throws {
        var config = ReadinessConfiguration()
        config.weights = [.hrv: 0.5, .vitals: 0.1]
        // Uncapped weighted mean would be (95×0.5 + 10×0.1) / 0.6 ≈ 80.8; the cap is 10 + 35 = 45.
        let result = try #require(ReadinessEngine.combine(
            [contributor(.hrv, 95, weight: 0.5), contributor(.vitals, 10, weight: 0.1)],
            configuration: config
        ))
        #expect(result.raw == 45)
        #expect(result.limitingFactor == .vitals)
    }

    @Test func severalRedFlagsCapHarder() throws {
        // HRV, resting HR and vitals all far off — the classic illness pattern.
        let result = try #require(ReadinessEngine.combine(
            [
                contributor(.hrv, 20, weight: 0.3), contributor(.restingHeartRate, 10, weight: 0.15),
                contributor(.vitals, 15, weight: 0.1), contributor(.sleep, 90, weight: 0.25),
                contributor(.trainingLoad, 85, weight: 0.2),
            ],
            configuration: .default
        ))
        #expect(abs(result.raw - (10 + 35.0 / 3)) < 1e-9)
        #expect(Int((result.raw / 10).rounded()) == 2)
    }

    @Test func trainingLoadIsNeverALimitingFactor() throws {
        let result = try #require(ReadinessEngine.combine(
            [contributor(.hrv, 80, weight: 0.3), contributor(.trainingLoad, 10, weight: 0.2)],
            configuration: .default
        ))
        #expect(result.limitingFactor == nil)
        #expect(abs(result.raw - (80 * 0.3 + 10 * 0.2) / 0.5) < 1e-9)
    }

    @Test func weightsAreRenormalisedOverAvailableContributors() throws {
        let result = try #require(ReadinessEngine.combine(
            [contributor(.hrv, 80, weight: 0.3), contributor(.sleep, 60, weight: 0.25)],
            configuration: .default
        ))
        #expect(abs(result.contributors.reduce(0) { $0 + $1.effectiveWeight } - 1) < 1e-9)
        #expect(abs(result.raw - (80 * 0.3 + 60 * 0.25) / 0.55) < 1e-9)
        #expect(result.limitingFactor == nil)
    }

    @Test func refusesToScoreFromTooLittleOfTheModel() {
        #expect(ReadinessEngine.combine([contributor(.trainingLoad, 80, weight: 0.2)], configuration: .default) == nil)
    }

    @Test func higherHRVGivesHigherSubscore() throws {
        func todayHRVSubscore(multiplier: Double) throws -> Double {
            var raw = Fixture.demo()
            let cutoff = Fixture.time(-1, 18)
            raw.hrv = raw.hrv.map { $0.date >= cutoff ? TimedValue(date: $0.date, value: $0.value * multiplier) : $0 }
            return try #require(engine.analyze(raw, now: Fixture.now).today?.contributor(.hrv)).subscore
        }
        #expect(try todayHRVSubscore(multiplier: 1.4) > todayHRVSubscore(multiplier: 1.0))
        #expect(try todayHRVSubscore(multiplier: 1.0) > todayHRVSubscore(multiplier: 0.6))
    }

    @Test func trendsHaveNormalRanges() {
        let analysis = engine.analyze(Fixture.demo(), now: Fixture.now)
        let hrv = analysis.trend(.hrv, lastDays: 30)
        #expect(hrv.count == 30)
        #expect(hrv.last?.normalRange != nil)
        let load = analysis.loadTrend(lastDays: 30)
        #expect(load.count == 30)
        #expect(load.last?.chronic != nil)
    }
}
