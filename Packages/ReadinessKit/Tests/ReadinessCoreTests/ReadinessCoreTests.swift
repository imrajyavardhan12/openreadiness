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
            let scale = { (sample: TimedValue) in
                sample.date >= cutoff ? TimedValue(date: sample.date, value: sample.value * multiplier) : sample
            }
            raw.hrv = raw.hrv.map(scale)
            raw.rmssd = raw.rmssd.map(scale)
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

// MARK: - Snapshot

@Suite struct SnapshotTests {
    @Test func staleScoreIsNeverShownAsToday() throws {
        let analysis = ReadinessEngine(calendar: Fixture.calendar).analyze(Fixture.demo(), now: Fixture.now)
        let snapshot = ReadinessSnapshot(analysis: analysis)
        #expect(snapshot.score(on: Fixture.now, calendar: Fixture.calendar) != nil)
        let tomorrow = Fixture.calendar.date(byAdding: .day, value: 1, to: Fixture.now)!
        #expect(snapshot.score(on: tomorrow, calendar: Fixture.calendar) == nil)
    }

    @Test func roundTripsAndKeepsAWeek() throws {
        let analysis = ReadinessEngine(calendar: Fixture.calendar).analyze(Fixture.demo(), now: Fixture.now)
        let snapshot = ReadinessSnapshot(analysis: analysis, isSampleData: true)
        #expect(snapshot.week.count == 7)
        #expect(snapshot.week.last?.day == Fixture.day(0))
        let decoded = try ReadinessSnapshot.decode(snapshot.encoded())
        #expect(decoded == snapshot)
        #expect(decoded.isSampleData)
    }
}

// MARK: - RMSSD

@Suite struct RMSSDTests {
    /// Beats at the given RR intervals (ms), starting at t = 0.
    func beats(_ intervals: [Double], gapBefore: Set<Int> = []) -> [Heartbeat] {
        var t = 0.0
        var result = [Heartbeat(time: 0)]
        for (index, rr) in intervals.enumerated() {
            t += rr / 1000
            result.append(Heartbeat(time: t, precededByGap: gapBefore.contains(index + 1)))
        }
        return result
    }

    @Test func alternatingIntervalsGiveTheirDifference() throws {
        // RR alternates 800/850 ms → every successive difference is ±50 ms → RMSSD = 50.
        let rr = (0..<40).map { $0.isMultiple(of: 2) ? 800.0 : 850.0 }
        #expect(abs(try #require(RMSSD.compute(beats(rr))) - 50) < 1e-6)
    }

    @Test func constantRhythmHasZeroVariability() throws {
        #expect(try #require(RMSSD.compute(beats(Array(repeating: 1000, count: 30)))) == 0)
    }

    @Test func ectopicBeatsAndImplausibleIntervalsAreRejected() throws {
        var rr = (0..<40).map { $0.isMultiple(of: 2) ? 800.0 : 850.0 }
        rr[10] = 400   // premature beat: >20% jump either side
        rr[20] = 2500  // missed beat: implausible interval
        #expect(abs(try #require(RMSSD.compute(beats(rr))) - 50) < 1e-6)
    }

    @Test func gapsBreakTheSequence() throws {
        // Without gap handling, the 1-second jump across the gap would dominate.
        let rr = (0..<40).map { $0.isMultiple(of: 2) ? 800.0 : 850.0 }
        let withGap = beats(rr, gapBefore: [15])
        #expect(abs(try #require(RMSSD.compute(withGap)) - 50) < 1e-6)
    }

    @Test func tooFewCleanBeatsReturnsNil() {
        #expect(RMSSD.compute(beats([800, 850, 800, 850])) == nil)
        #expect(RMSSD.compute([]) == nil)
    }

    @Test func scorerPrefersRMSSDOnceItHasABaseline() throws {
        let engine = ReadinessEngine(calendar: Fixture.calendar)
        let withRMSSD = try #require(engine.analyze(Fixture.demo(), now: Fixture.now).today?.contributor(.hrv))
        #expect(withRMSSD.components.first?.label.contains("RMSSD") == true)

        var sdnnOnly = Fixture.demo()
        sdnnOnly.rmssd = []
        let fallback = try #require(engine.analyze(sdnnOnly, now: Fixture.now).today?.contributor(.hrv))
        #expect(fallback.components.first?.label.contains("SDNN") == true)
    }
}

// MARK: - Export

@Suite struct ExportTests {
    @Test func escapesPerRFC4180() {
        #expect(CSVWriter.escape("plain") == "plain")
        #expect(CSVWriter.escape("a,b") == "\"a,b\"")
        #expect(CSVWriter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVWriter.escape("two\nlines") == "\"two\nlines\"")
    }

    @Test func numbersIgnoreDeviceLocale() {
        #expect(CSVWriter.number(1234.567) == "1234.57")
        #expect(CSVWriter.number(nil) == "")
        #expect(CSVWriter.number(.nan) == "")
    }

    @Test func readinessCSVHasOneRowPerDayAndMatchingColumns() throws {
        let analysis = ReadinessEngine(calendar: Fixture.calendar).analyze(Fixture.demo(), now: Fixture.now)
        let csv = ReadinessExport.csv(analysis, calendar: Fixture.calendar)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == analysis.days.count + 1)
        let columns = lines[0].components(separatedBy: ",").count
        #expect(lines.allSatisfy { $0.components(separatedBy: ",").count == columns })
        let last = lines.last!.components(separatedBy: ",")
        #expect(last[0] == "2026-09-25")
        #expect(Int(last[1]) == analysis.today?.score)
    }
}
