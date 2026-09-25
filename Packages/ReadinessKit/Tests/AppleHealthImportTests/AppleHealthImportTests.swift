import Foundation
import Testing
@testable import AppleHealthImport
import HealthInsights
import ReadinessCore

/// Synthetic export covering the awkward parts of real files. No real health data is used in tests.
enum ExportFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 30 beats alternating 800/850 ms (RMSSD 50), with U+202F before AM like recent iOS exports.
    static var beats: String {
        var t = 3 * 3600.0 + 10 * 60 // 03:10:00
        var lines: [String] = []
        for i in 0..<31 {
            let h = Int(t) / 3600, m = Int(t) % 3600 / 60, s = t.truncatingRemainder(dividingBy: 60)
            lines.append("<InstantaneousBeatsPerMinute bpm=\"72\" time=\"\(h):\(String(format: "%02d", m)):\(String(format: "%05.2f", s))\u{202F}AM\"/>")
            t += i.isMultiple(of: 2) ? 0.80 : 0.85
        }
        return lines.joined(separator: "\n")
    }

    static var xml: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE HealthData [
        <!ELEMENT HealthData (ExportDate,Me,(Record|Workout|ActivitySummary)*)>
        ]>
        <HealthData locale="en_US">
         <ExportDate value="2026-09-25 15:34:00 +0000"/>
         <Me HKCharacteristicTypeIdentifierDateOfBirth="1990-06-01"/>
         <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" sourceName="Watch" unit="ms" startDate="2026-09-24 03:10:00 +0000" endDate="2026-09-24 03:11:00 +0000" value="48">
          <HeartRateVariabilityMetadataList>
        \(beats)
          </HeartRateVariabilityMetadataList>
         </Record>
         <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Watch" startDate="2026-09-23 23:00:00 +0000" endDate="2026-09-24 03:00:00 +0000" value="HKCategoryValueSleepAnalysisAsleepCore"/>
         <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Watch" startDate="2026-09-24 03:00:00 +0000" endDate="2026-09-24 04:00:00 +0000" value="HKCategoryValueSleepAnalysisAsleepDeep"/>
         <Record type="HKQuantityTypeIdentifierStepCount" sourceName="iPhone" unit="count" startDate="2026-09-24 09:00:00 +0000" endDate="2026-09-24 10:00:00 +0000" value="4000"/>
         <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Watch" unit="count" startDate="2026-09-24 09:00:00 +0000" endDate="2026-09-24 10:00:00 +0000" value="3000"/>
         <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Watch" unit="count" startDate="2026-09-24 18:00:00 +0000" endDate="2026-09-24 19:00:00 +0000" value="2500"/>
         <Record type="HKQuantityTypeIdentifierActiveEnergyBurned" sourceName="Watch" unit="kJ" startDate="2026-09-24 18:00:00 +0000" endDate="2026-09-24 19:00:00 +0000" value="418.4"/>
         <Record type="HKQuantityTypeIdentifierOxygenSaturation" sourceName="Watch" unit="%" startDate="2026-09-24 02:00:00 +0000" endDate="2026-09-24 02:00:00 +0000" value="0.97"/>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Watch" unit="count/min" startDate="2026-09-24 02:05:00 +0000" endDate="2026-09-24 02:05:00 +0000" value="50"/>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Watch" unit="count/min" startDate="2026-09-24 02:10:00 +0000" endDate="2026-09-24 02:10:00 +0000" value="54"/>
         <Record type="HKQuantityTypeIdentifierRestingHeartRate" sourceName="Watch" unit="count/min" startDate="2026-09-24 00:00:00 +0000" endDate="2026-09-24 23:59:00 +0000" value="58"/>
         <Record type="HKQuantityTypeIdentifierEstimatedWorkoutEffortScore" sourceName="Watch" unit="appleEffortScore" startDate="2026-09-24 18:10:00 +0000" endDate="2026-09-24 18:10:00 +0000" value="7"/>
         <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="40" durationUnit="min" sourceName="Watch" startDate="2026-09-24 18:00:00 +0000" endDate="2026-09-24 18:40:00 +0000">
          <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" startDate="2026-09-24 18:00:00 +0000" endDate="2026-09-24 18:40:00 +0000" average="152" minimum="95" maximum="171" unit="count/min"/>
          <WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" startDate="2026-09-24 18:00:00 +0000" endDate="2026-09-24 18:40:00 +0000" sum="420" unit="kcal"/>
          <WorkoutStatistics type="HKQuantityTypeIdentifierDistanceWalkingRunning" startDate="2026-09-24 18:00:00 +0000" endDate="2026-09-24 18:40:00 +0000" sum="7.5" unit="km"/>
         </Workout>
         <ActivitySummary dateComponents="2026-09-24" activeEnergyBurned="512" activeEnergyBurnedGoal="500" activeEnergyBurnedUnit="kcal" appleExerciseTime="45" appleExerciseTimeGoal="30" appleStandHours="11" appleStandHoursGoal="12"/>
        </HealthData>
        """
    }

    static func parse() throws -> ImportedHealthData {
        try AppleHealthExport.parse(data: Data(xml.utf8), calendar: calendar)
    }
}

@Suite struct ExportDateTests {
    @Test func parsesWithTimeZoneOffsets() throws {
        let utc = try #require(ExportDates.parse("2026-09-24 21:03:11 +0000"))
        let india = try #require(ExportDates.parse("2026-09-25 02:33:11 +0530"))
        let newYork = try #require(ExportDates.parse("2026-09-24 17:03:11 -0400"))
        #expect(utc == india)
        #expect(utc == newYork)
        #expect(utc.timeIntervalSince1970 == 1_790_283_791)
        #expect(ExportDates.parse("not a date") == nil)
    }

    @Test func civilDays() {
        #expect(ExportDates.daysFromCivil(year: 1970, month: 1, day: 1) == 0)
        #expect(ExportDates.daysFromCivil(year: 2000, month: 3, day: 1) == 11_017)
    }

    @Test func beatClockTimesHandleNarrowSpacesAndMeridiem() {
        let evening: Double = 78_083.45 // 21:41:23.45
        let noon: Double = 43_201      // 12:00:01
        #expect(ExportDates.secondsOfDay("9:41:23.45\u{202F}PM") == evening)
        #expect(ExportDates.secondsOfDay("12:00:01.00 AM") == 1)
        #expect(ExportDates.secondsOfDay("12:00:01.00 PM") == noon)
        #expect(ExportDates.secondsOfDay("21:41:23.45") == evening)
    }

    @Test func beatsCrossingMidnightKeepIncreasing() {
        let beats = ExportDates.heartbeats(fromClockTimes: [86_399.2, 86_399.9, 0.6, 1.3])
        let rounded: [Double] = beats.map { ($0.time * 10).rounded() / 10 }
        let expected: [Double] = [0, 0.7, 1.4, 2.1]
        #expect(rounded == expected)
    }
}

@Suite struct AppleHealthExportTests {
    @Test func readinessInputs() throws {
        let data = try ExportFixture.parse()
        let raw = data.raw
        #expect(raw.hrv.map(\.value) == [48])
        let rmssd = try #require(raw.rmssd.first?.value)
        #expect(abs(rmssd - 50) < 0.5, "RMSSD from exported beats (U+202F separators)")
        #expect(raw.sleep.count == 2)
        #expect(raw.oxygenSaturation.first?.value == 97)
        #expect(raw.restingHeartRate.first?.value == 58)
        #expect(raw.heartRateBuckets.first?.value == 52)
        #expect(raw.profile.age == 36)
        #expect(abs((raw.activeEnergyDaily.first?.value ?? 0) - 100) < 1e-9, "kJ converted to kcal")
    }

    @Test func workoutsGetStatsAndEffort() throws {
        let data = try ExportFixture.parse()
        let workout = try #require(data.raw.workouts.first)
        #expect(workout.activityName == "Running")
        #expect(workout.averageHeartRate == 152)
        #expect(workout.effortScore == 7)
        #expect(workout.effortIsEstimated)
        let summary = try #require(data.workouts.first)
        #expect(summary.distanceMeters == 7500)
        #expect(summary.maxHeartRate == 171)
        // Stable identity across re-imports.
        #expect(try ExportFixture.parse().workouts.first?.id == summary.id)
    }

    @Test func cumulativeTotalsAreNotDoubleCounted() throws {
        let steps = try #require(try ExportFixture.parse().daily[.steps]?.first)
        // iPhone 4000 vs Watch 3000 + 2500 = 5500 → the larger single source, not 9500.
        #expect(steps.value == 5500)
    }

    @Test func ringsAndMetadata() throws {
        let data = try ExportFixture.parse()
        let ring = try #require(data.rings.first)
        #expect(ring.move == 512)
        #expect(ring.standGoal == 12)
        #expect(data.exportDate == ExportDates.parse("2026-09-25 15:34:00 +0000"))
        #expect(data.coverage != nil)
    }

    @Test func rejectsNonExports() {
        #expect(throws: (any Error).self) {
            try AppleHealthExport.parse(data: Data("<Other/>".utf8), calendar: ExportFixture.calendar)
        }
    }

    @Test func activityNames() {
        #expect(ExportTypes.activityName("HKWorkoutActivityTypeFunctionalStrengthTraining") == "Functional Strength Training")
        #expect(ExportTypes.activityName("HKWorkoutActivityTypeHighIntensityIntervalTraining") == "HIIT")
    }
}
