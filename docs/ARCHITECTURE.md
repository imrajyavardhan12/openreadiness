# Architecture

```
┌────────────────────────── iPhone app (SwiftUI) ──────────────────────────┐
│  Today · Trends · History · About          ReadinessStore (@Observable)  │
│  Swift Charts: trend + normal band,        fetch → analyze (off-main)    │
│  hypnogram, load, calendar heatmap         → publish → push to watch     │
└───────────────┬──────────────────────────────────────┬───────────────────┘
                │ RawHealthData                        │ WatchPayload (WCSession
┌───────────────┴───────────────┐                      │ applicationContext)
│ ReadinessHealthKit            │               ┌──────┴────────────────────┐
│ HealthKitDataSource           │               │ Watch app (SwiftUI)       │
│ (read-only, async queries)    │               │ phone score, else local   │
└───────────────┬───────────────┘               └───────────────────────────┘
                │
┌───────────────┴──────────────────────────────────────────────────────────┐
│ HealthInsights (pure Swift): metric catalogue, series analytics,         │
│  normal bands, period comparison, streaks, histograms, Spearman          │
│  correlation + curated insights, sleep schedule, heart-rate zones        │
├──────────────────────────────────────────────────────────────────────────┤
│ ReadinessCore (pure Swift, no HealthKit/UI, unit-tested on macOS)        │
│  Models: RawHealthData → DayMetrics → Contributor → ReadinessScore       │
│  Analysis: SleepAnalyzer, DayMetricsBuilder, WorkoutLoadModel, Stats     │
│  Scoring: contributor scorers, SleepScorer, ReadinessEngine, trends      │
│  Demo: deterministic synthetic data (Simulator, previews, tests)         │
└──────────────────────────────────────────────────────────────────────────┘
```

## Principles

- **A pure core.** `ReadinessEngine.analyze(raw, now:)` is deterministic and has no side effects. All
  logic is testable with `swift test` in seconds, with no device or Simulator needed.
- **HealthKit stays behind one protocol.** `HealthDataSource` has two implementations:
  `HealthKitDataSource` and `DemoDataSource`. HealthKit types never cross into the core or the UI.
- **HealthKit is the source of truth.** Nothing is cached to disk. Months of data are fetched in a
  few concurrent queries; heart rate is fetched as 30-minute statistics buckets rather than raw
  samples, which keeps memory and time low. Raw data stays in memory so settings changes recompute
  instantly.
- **Swift 6 strict concurrency.** Core value types are `Sendable`, the engine runs in a detached task,
  and the store is `@MainActor @Observable`.
- **Like-for-like comparisons.** Metrics with more than one source (overnight vs all-day HRV,
  sleeping vs Apple resting HR) are stored separately and never compared across flavours.
- **The phone owns history; the watch displays it.** A watch keeps only a short HealthKit history,
  so the phone computes the score and pushes it via `updateApplicationContext` (latest value wins).
  The watch computes locally only when the phone hasn't synced that day.

## Layout

```
Packages/ReadinessKit/           Swift package
  Sources/ReadinessCore/          engine (no platform dependencies)
  Sources/HealthInsights/         explorer analytics & insights (no platform dependencies)
  Sources/ReadinessHealthKit/     HealthKit adapters (readiness + explorer)
  Tests/ReadinessCoreTests/       Swift Testing suite
App/Shared/                       store, gauge, theme, watch sync (both apps)
App/iOS/                          iPhone app: views + charts
App/watchOS/                      watch app
project.yml                       XcodeGen spec (the .xcodeproj is generated)
docs/                             algorithm, research, architecture
```

## Data flow for one refresh

1. `ReadinessStore.refresh()` asks the source for `lookbackDays = history (90) + max(baseline 60, chronic 28) + 1` days.
2. `HealthKitDataSource.fetch` runs 9 queries concurrently and returns `RawHealthData`.
3. `ReadinessEngine.analyze` builds `DayMetrics` for each day, then scores each of the last 90 days
   using only data before that day.
4. The store publishes the new `ReadinessAnalysis` and sends today's score and the last week to the watch.
5. `HKObserverQuery` notifications (sleep, HRV, resting HR, workouts) trigger step 1 again.

## The explorer

`ExplorerStore` loads all 21 metrics concurrently, one `HKStatisticsCollectionQuery` each over
about 14 months, so HealthKit aggregates on its side and de-duplicates iPhone and Watch samples. A
failure in one metric never blocks the others. W/M/6M/Y are then slices of the in-memory series,
so switching range is instant. Longer ranges are bucketed into weeks or months (totals become
average daily totals, so a partial week compares fairly).

Intraday data (5-minute heart-rate buckets, hourly steps) and workout heart-rate samples are
fetched on demand, one day or one workout at a time.

**Insights** evaluate a curated list of plausible relationships (e.g. sleep duration → overnight
HRV, training load → next-night sleeping HR). They don't mine every pair: testing everything
against everything would mostly surface chance correlations. A finding is shown only with at
least 21 paired days, Spearman |ρ| ≥ 0.15 and |t| ≥ 2 (roughly p < 0.05). Every finding is
labelled as correlation, not causation.

**Performance notes:** chart selection state lives inside the chart view, so scrubbing never
recomputes the page's statistics. The 12-month heatmap draws 365 cells with one `Canvas`. Demo
data is generated off the main actor.

**Accessibility:** the main explorer chart implements `AXChartDescriptorRepresentable` (Audio
Graphs and data-table navigation for VoiceOver). Every mark and tile has a label. Colour is never
the only cue.

## Extending

- **Add a contributor:** add a case to `ContributorKind`, write a scorer in `ContributorScorers.swift`
  that returns a `Contributor`, add it to `ReadinessEngine.score`, and give it a default weight.
- **Tune the model:** everything is in `ReadinessConfiguration`.
- **New chart:** `ReadinessAnalysis.trend(_:lastDays:)` returns points with a personal normal range,
  ready for `MetricTrendChart`.
- **Add an explorer metric:** add a case to `HealthMetric` (title, unit, aggregation, explanation),
  map it in `HealthKitMetricsProvider.mapping(for:)`, and synthesise it in `DemoMetricsProvider`.
  It then appears on the dashboard with every analysis card automatically.
- **Add an insight:** append an `InsightCandidate` to `InsightCandidate.curated` with a rationale.
