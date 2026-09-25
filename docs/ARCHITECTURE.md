# Architecture

![OpenReadiness architecture: HealthKit feeds the ReadinessKit package (adapters, ReadinessCore, HealthInsights); the iPhone app publishes a snapshot to an App Group read by widgets and sends it to the watch; background delivery refreshes the snapshot while the app is closed.](diagrams/architecture.png)

<sub>Source: [`diagrams/architecture.html`](diagrams/architecture.html) (editable SVG, also exported as [`.svg`](diagrams/architecture.svg)).</sub>

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
App/Shared/                       store and watch sync (both apps)
App/SharedKit/                    theme, gauge, snapshot storage (apps + widget extensions)
App/WidgetShared/                 widget timeline provider + views (both widget extensions)
App/Widgets/                      iPhone widget extension
App/WatchWidgets/                 watch complication extension
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

## Widgets, complications and background refresh

Nothing outside the main app queries HealthKit. The app computes a `ReadinessSnapshot` (today's
score, its contributors and the last 7 days) and `SnapshotPublisher` writes it to the App Group
`group.org.openreadiness`. It then asks WidgetKit to reload, but only when the score actually
changed, because reloads are budgeted by the system.

- **iPhone widgets** (`App/Widgets`): small and medium Home Screen widgets, plus circular,
  rectangular and inline Lock Screen accessories.
- **Watch complications** (`App/WatchWidgets`): circular, rectangular, corner and inline. The watch
  writes its own snapshot, received from the phone or computed locally, into its own App Group
  container.
- **Staleness:** each timeline has a second entry at midnight. `ReadinessSnapshot.score(on:)`
  returns nil once the day is over, so a widget shows "–" rather than yesterday's number.
- **Background delivery** (`BackgroundRefresher`): observer queries on sleep, HRV, resting heart
  rate and workouts, with `enableBackgroundDelivery(… .hourly)`. They are registered at every
  launch from the app delegate, which iOS requires for delivery to a terminated app. The score is
  recomputed headlessly (60-day lookback, 7 scored days) and published, and the handler always
  calls HealthKit's completion block. Health data is encrypted while the phone is locked, so a
  delivery at night may find it unreadable (`errorDatabaseInaccessible`). That case is logged, and
  the next delivery after unlock catches up. While the app is in the foreground, `ReadinessStore`
  does the work instead.
- **Code sharing:** `App/SharedKit` (theme, gauge, snapshot storage) and `App/WidgetShared`
  (provider and views) compile into the extensions. HealthKit and WatchConnectivity code never do.
- **Reviewing widget UI:** debug builds add *About › Developer › Widget gallery*, which renders
  every family and state (good day, poor day, no score, dark mode). The UI test suite screenshots
  it.

## Data sources

`DataMode` selects one of three sources. Both stores switch together, and the UI marks which one is
showing.

| Mode | Readiness (`HealthDataSource`) | Explorer (`HealthMetricsProvider`) |
|---|---|---|
| `health` | `HealthKitDataSource` | `HealthKitMetricsProvider` |
| `sample` | `DemoDataSource` | `DemoMetricsProvider` |
| `imported` | `ImportedDataSource` | `ImportedMetricsProvider` |

**Import** (`AppleHealthImport`, driven by `ImportController`):
- `export.xml` is streamed once and saved as a binary property list (about 1.5% of the XML's size)
  with file protection. Later launches decode it in well under a second.
- In imported mode, scoring treats the end of the export as "now". Nothing is published to widgets
  or the watch, which keep live data.
- Exports aren't de-duplicated, so cumulative totals take the largest single source per day or hour.

**Heart-rate averages** are time-weighted in every mode: hourly means first, then the daily mean
(`SeriesAnalytics.dailyFromHourly`). The watch samples every few seconds during workouts, so a plain
sample mean would mostly describe workouts.

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
