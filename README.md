# OpenReadiness

**An open-source, on-device readiness score and health data explorer for every Apple Watch, not just Series 12.**

watchOS 27 introduced a 0–10 Readiness score, but only on Apple Watch Series 12 and Ultra 4.
OpenReadiness builds a comparable score from HealthKit data that older watches already record: HRV,
sleeping heart rate, sleep, training load and overnight vitals. It shows exactly how each point was
calculated, and every metric is charted against *your own* normal range.

- **Transparent.** Each contributor shows its inputs, your baseline, its z-score, its weight and
  how many points it added or removed. The full method is in [docs/ALGORITHM.md](docs/ALGORITHM.md).
- **Personal.** Everything is compared with your last 60 days, using outlier-resistant statistics.
- **Private.** It computes on-device and only reads from Health. It has no servers, accounts or analytics.
- **Better charts.** Trends show a shaded personal normal band, plus a sleep hypnogram, acute vs
  chronic training load, a calendar heatmap of scores, and tap-to-scrub values.
- **A full health explorer.** It covers 21 Apple Watch metrics and shows where Apple Health falls
  short (see below).
- **Familiar.** The bands are the same as Apple's: Recover 0–1 · Pace Yourself 2–4 · Ready 5–7 · Go For It 8–10.

> Not a medical device. Not affiliated with Apple.

## Beyond Apple Health

| Apple Health | OpenReadiness |
|---|---|
| A chart with no sense of what's normal for you | A personal normal band and a 7-day average on every metric |
| One chart per metric | This period vs the last one, records and streaks, a day-of-week pattern, a distribution, and a 12-month heatmap |
| Heart rate as a cloud of dots | Daily min–max range bars, and a 24-hour timeline with sleep and workouts shaded in |
| Sleep one night at a time | A bedtime and wake chart, regularity, weekend drift ("social jetlag"), and stage trends |
| Workouts as a list | Weekly volume by activity, per-workout heart rate on zone bands, and time in zones |
| Metrics in isolation | **Insights**, automatic findings about what relates to what for you (e.g. "Overnight HRV is higher after longer sleep"), with ρ and sample size, plus a scatter-plot explorer |
| A rings history that's hard to browse | A month grid of rings with closure rates |

The explorer covers these metrics. **Heart:** heart rate, resting, walking, HRV, heart-rate
recovery, cardio fitness (VO₂ max). **Activity:** steps, active energy, exercise, stand, distance,
flights. **Respiratory and body:** respiratory rate, blood oxygen, wrist temperature. **Mobility:**
walking speed, step length, asymmetry. **Environment:** sound exposure, headphone audio, time in
daylight.

Reference lines are shown only where there's solid evidence, each with its source: 8,000 steps
(Paluch 2022), 30 exercise minutes (WHO), heart-rate recovery above 12 bpm (Cole, NEJM 1999),
80 dB for noise (WHO), and SpO₂ 95–100 %.

## How the score works (short version)

| Contributor | Weight | What it measures |
|---|---|---|
| Heart rate variability | 30 % | Overnight SDNN vs. your 60-day normal (log scale), blended with 7-day trend |
| Sleep | 25 % | Sleep score (duration 50 · bedtime consistency 30 · interruptions 20) + sleep debt |
| Training load | 20 % | Last 7 days vs. prior 3 weeks (session-RPE: minutes × effort) |
| Resting heart rate | 15 % | Lowest 30-min average while asleep vs. your normal |
| Overnight vitals | 10 % | Respiratory rate, wrist temperature, SpO₂ outside your range |

Exactly your normal scores 70 per contributor, which works out to a 7 (*Ready*). Missing signals have
their weight shared among the rest. A very poor HRV, resting HR, sleep or vitals score caps the
total so illness isn't averaged away. See [docs/ALGORITHM.md](docs/ALGORITHM.md) for every constant
and its rationale.

## Requirements

| | Minimum |
|---|---|
| iPhone | iOS 17 |
| Apple Watch | watchOS 10 (Series 4 or later). Any watch that syncs HRV and sleep to Health works for the iPhone app |
| Build | Xcode 16+ (developed with Xcode 27), [XcodeGen](https://github.com/yonaskolb/XcodeGen) |

Signal availability depends on the watch. Wrist temperature needs Series 8 or later, and blood
oxygen needs Series 6 or later where the feature is offered. Effort ratings need watchOS 11. The
score adapts to whatever is available.

## Getting started

```bash
brew install xcodegen
xcodegen generate
open OpenReadiness.xcodeproj
```

1. Select your team under *Signing & Capabilities* for both targets (HealthKit requires signing).
2. Run on your iPhone. The watch app installs alongside it.
3. No watch or no data yet? Tap **Explore with sample data** or pass the `-demo` launch argument.
   The Simulator also works with sample data.

Engine and analytics tests (fast, no Simulator needed):

```bash
cd Packages/ReadinessKit && swift test
```

UI walkthrough, which also generates screenshots of every screen: press **⌘U** in Xcode.

## Project structure

```
Packages/ReadinessKit/     Pure-Swift scoring engine (ReadinessCore), explorer analytics
                           (HealthInsights) + HealthKit adapters
App/iOS/                   iPhone app: Today, Health, Workouts, Insights, About
App/watchOS/               Watch app: score, contributors, week
App/Shared/                Store, gauge, theme, watch sync
docs/                      ALGORITHM · ARCHITECTURE · RESEARCH
```

More detail is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Background research on Apple,
Oura, Whoop and Garmin is in [docs/RESEARCH.md](docs/RESEARCH.md).

## Roadmap

- [ ] Watch-face complications and a Home Screen widget (WidgetKit)
- [ ] RMSSD from beat-to-beat `HKHeartbeatSeriesSample` data (more sensitive than SDNN)
- [ ] Intraday updates (naps, daytime heart rate), as Apple does
- [ ] Menstrual-cycle-aware temperature and resting-HR baselines
- [ ] Localisation (String Catalogs are enabled)
- [ ] Optional subjective check-in (energy/soreness) to validate and tune the weights
- [ ] CSV export of daily metrics and scores

## Privacy

See [PRIVACY.md](PRIVACY.md). In short, data never leaves your devices. The iPhone sends today's
score to your own watch using WatchConnectivity, and that is the only transfer.

## Contributing

Issues and pull requests are welcome, especially validation data, algorithm critiques with
references, and accessibility improvements. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
