import Foundation

public enum MetricCategory: String, Sendable, Hashable, CaseIterable, Identifiable {
    case heart
    case activity
    case respiratory
    case mobility
    case environment

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heart: "Heart"
        case .activity: "Activity"
        case .respiratory: "Respiratory & Body"
        case .mobility: "Mobility"
        case .environment: "Environment"
        }
    }

    public var systemImage: String {
        switch self {
        case .heart: "heart.fill"
        case .activity: "flame.fill"
        case .respiratory: "lungs.fill"
        case .mobility: "figure.walk"
        case .environment: "sun.max.fill"
        }
    }
}

/// How daily values are combined and charted.
public enum Aggregation: Sendable, Hashable {
    /// Daily totals (steps, energy). Bars.
    case sum
    /// Daily mean of discrete readings (HRV, SpO₂). Line with a personal normal band.
    case average
    /// Daily min / mean / max (heart rate). Floating range bars.
    case range
}

/// A labelled region of values with a general meaning (not personal), e.g. SpO₂ 95–100 % "Typical".
public struct ReferenceBand: Sendable, Hashable, Identifiable {
    public enum Tone: Sendable, Hashable { case good, neutral, caution }

    public var label: String
    public var lower: Double
    public var upper: Double
    public var tone: Tone
    public var id: String { label }

    public init(_ label: String, _ lower: Double, _ upper: Double, _ tone: Tone) {
        self.label = label
        self.lower = lower
        self.upper = upper
        self.tone = tone
    }
}

/// Every Apple Watch metric the explorer can show. The HealthKit mapping lives in the adapter;
/// this type holds only presentation and analysis semantics, so it stays platform-independent.
public enum HealthMetric: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    // Heart
    case heartRate
    case restingHeartRate
    case walkingHeartRate
    case hrv
    case heartRateRecovery
    case vo2Max
    // Activity
    case steps
    case activeEnergy
    case exerciseTime
    case standTime
    case distance
    case flightsClimbed
    // Respiratory & body
    case respiratoryRate
    case oxygenSaturation
    case wristTemperature
    // Mobility
    case walkingSpeed
    case walkingStepLength
    case walkingAsymmetry
    // Environment
    case environmentalAudio
    case headphoneAudio
    case timeInDaylight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heartRate: "Heart Rate"
        case .restingHeartRate: "Resting Heart Rate"
        case .walkingHeartRate: "Walking Heart Rate"
        case .hrv: "Heart Rate Variability"
        case .heartRateRecovery: "Heart Rate Recovery"
        case .vo2Max: "Cardio Fitness"
        case .steps: "Steps"
        case .activeEnergy: "Active Energy"
        case .exerciseTime: "Exercise Minutes"
        case .standTime: "Stand Minutes"
        case .distance: "Walking + Running Distance"
        case .flightsClimbed: "Flights Climbed"
        case .respiratoryRate: "Respiratory Rate"
        case .oxygenSaturation: "Blood Oxygen"
        case .wristTemperature: "Wrist Temperature"
        case .walkingSpeed: "Walking Speed"
        case .walkingStepLength: "Step Length"
        case .walkingAsymmetry: "Walking Asymmetry"
        case .environmentalAudio: "Environmental Sound"
        case .headphoneAudio: "Headphone Audio"
        case .timeInDaylight: "Time in Daylight"
        }
    }

    public var shortTitle: String {
        switch self {
        case .restingHeartRate: "Resting HR"
        case .walkingHeartRate: "Walking HR"
        case .hrv: "HRV"
        case .heartRateRecovery: "HR Recovery"
        case .distance: "Distance"
        case .environmentalAudio: "Noise"
        default: title
        }
    }

    public var category: MetricCategory {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRate, .hrv, .heartRateRecovery, .vo2Max: .heart
        case .steps, .activeEnergy, .exerciseTime, .standTime, .distance, .flightsClimbed: .activity
        case .respiratoryRate, .oxygenSaturation, .wristTemperature: .respiratory
        case .walkingSpeed, .walkingStepLength, .walkingAsymmetry: .mobility
        case .environmentalAudio, .headphoneAudio, .timeInDaylight: .environment
        }
    }

    public var unit: String {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRate, .heartRateRecovery: "bpm"
        case .hrv: "ms"
        case .vo2Max: "VO₂ max"
        case .steps: "steps"
        case .activeEnergy: "kcal"
        case .exerciseTime, .standTime, .timeInDaylight: "min"
        case .distance: "km"
        case .flightsClimbed: "floors"
        case .respiratoryRate: "br/min"
        case .oxygenSaturation, .walkingAsymmetry: "%"
        case .wristTemperature: "°C"
        case .walkingSpeed: "km/h"
        case .walkingStepLength: "cm"
        case .environmentalAudio, .headphoneAudio: "dB"
        }
    }

    public var fractionDigits: Int {
        switch self {
        case .distance, .respiratoryRate, .vo2Max, .walkingSpeed, .walkingAsymmetry: 1
        case .wristTemperature: 2
        default: 0
        }
    }

    public var aggregation: Aggregation {
        switch self {
        case .heartRate: .range
        case .steps, .activeEnergy, .exerciseTime, .standTime, .distance, .flightsClimbed, .timeInDaylight: .sum
        default: .average
        }
    }

    /// nil when neither direction is inherently better.
    public var higherIsBetter: Bool? {
        switch self {
        case .hrv, .heartRateRecovery, .vo2Max, .steps, .activeEnergy, .exerciseTime, .standTime,
             .distance, .flightsClimbed, .walkingSpeed, .walkingStepLength, .timeInDaylight: true
        case .restingHeartRate, .walkingHeartRate, .walkingAsymmetry, .environmentalAudio, .headphoneAudio: false
        case .heartRate, .respiratoryRate, .oxygenSaturation, .wristTemperature: nil
        }
    }

    /// Recorded only occasionally (a few times a week or less): drawn as points, never as a daily line.
    public var isSparse: Bool {
        switch self {
        case .vo2Max, .heartRateRecovery, .walkingSpeed, .walkingStepLength, .walkingAsymmetry: true
        default: false
        }
    }

    public var systemImage: String {
        switch self {
        case .heartRate: "heart.fill"
        case .restingHeartRate: "heart"
        case .walkingHeartRate: "figure.walk.motion"
        case .hrv: "waveform.path.ecg"
        case .heartRateRecovery: "arrow.down.heart"
        case .vo2Max: "lungs"
        case .steps: "shoeprints.fill"
        case .activeEnergy: "flame.fill"
        case .exerciseTime: "figure.run"
        case .standTime: "figure.stand"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .flightsClimbed: "figure.stairs"
        case .respiratoryRate: "wind"
        case .oxygenSaturation: "drop.fill"
        case .wristTemperature: "thermometer.medium"
        case .walkingSpeed: "speedometer"
        case .walkingStepLength: "ruler"
        case .walkingAsymmetry: "figure.walk"
        case .environmentalAudio: "ear"
        case .headphoneAudio: "headphones"
        case .timeInDaylight: "sun.max.fill"
        }
    }

    /// A daily target drawn as a reference line on bar charts, with its source.
    public var referenceGoal: (value: Double, note: String)? {
        switch self {
        case .steps: (8000, "About 8,000 steps a day is associated with most of the long-term health benefit in large studies (Paluch et al., 2022).")
        case .exerciseTime: (30, "WHO recommends at least 150 minutes of moderate activity a week — about 30 minutes a day.")
        case .timeInDaylight: (60, "Daylight exposure supports your body clock and sleep; many clinicians suggest an hour or more outdoors.")
        default: nil
        }
    }

    /// General (non-personal) interpretation ranges, where well established.
    public var referenceBands: [ReferenceBand] {
        switch self {
        case .oxygenSaturation:
            [ReferenceBand("Typical", 95, 100, .good), ReferenceBand("Below typical", 90, 95, .caution)]
        case .respiratoryRate:
            [ReferenceBand("Typical adult range", 12, 20, .good)]
        case .heartRateRecovery:
            [ReferenceBand("Healthy (>12 bpm)", 12, 80, .good), ReferenceBand("Low (≤12 bpm)", 0, 12, .caution)]
        case .environmentalAudio, .headphoneAudio:
            [ReferenceBand("OK", 0, 80, .good), ReferenceBand("Loud (≥80 dB)", 80, 120, .caution)]
        default:
            []
        }
    }

    public var explanation: String {
        switch self {
        case .heartRate:
            "Each bar spans your lowest to highest heart rate that day; the dot is the daily average. Wide ranges are normal on active days."
        case .restingHeartRate:
            "Apple's daily estimate of your heart rate at rest. A sustained rise can reflect fatigue, illness, heat, alcohol or stress; a gradual fall often follows improving fitness."
        case .walkingHeartRate:
            "Your average heart rate while walking at a steady pace. It tends to drop as cardiovascular fitness improves."
        case .hrv:
            "Heart rate variability (SDNN) measured by your watch several times a day. It's very personal — compare it only with your own normal range, never with other people."
        case .heartRateRecovery:
            "How much your heart rate falls in the first minute after a workout ends. Faster recovery generally indicates better fitness; a drop of 12 bpm or less has been linked to higher cardiovascular risk (Cole et al., NEJM 1999)."
        case .vo2Max:
            "Cardio fitness: an estimate of the maximum oxygen your body can use, recorded during outdoor walks, runs and hikes. One of the strongest predictors of long-term health."
        case .steps:
            "Total steps counted by your iPhone and Apple Watch."
        case .activeEnergy:
            "Calories burned through movement, on top of what your body uses at rest. This is your Move ring."
        case .exerciseTime:
            "Minutes of activity at or above a brisk walk. This is your Exercise ring."
        case .standTime:
            "Minutes you spent standing and moving around."
        case .distance:
            "Distance covered on foot, from walking and running."
        case .flightsClimbed:
            "Flights of stairs climbed, measured by the barometric altimeter."
        case .respiratoryRate:
            "Breaths per minute, measured by your watch while you sleep. A sudden rise above your normal can accompany illness."
        case .oxygenSaturation:
            "Blood oxygen measured in the background, mostly overnight. Wrist readings are less precise than a medical pulse oximeter; look at trends rather than single values."
        case .wristTemperature:
            "Your nightly wrist temperature. Health shows it relative to your baseline; changes follow the menstrual cycle, illness, alcohol and room temperature."
        case .walkingSpeed:
            "Your typical walking speed on flat ground. Walking speed is a well-studied marker of overall health and mobility."
        case .walkingStepLength:
            "The average length of your steps while walking."
        case .walkingAsymmetry:
            "How often one step takes a different time from the other. Lower is better; a rise can follow injury."
        case .environmentalAudio:
            "Average sound levels around you. Long exposure above 80 dB can damage hearing over time (WHO)."
        case .headphoneAudio:
            "Average listening level through headphones. Keep weekly exposure below 80 dB to protect your hearing."
        case .timeInDaylight:
            "Time spent in daylight, measured by the ambient light sensor on Apple Watch (watchOS 10+)."
        }
    }
}
