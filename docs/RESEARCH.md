# Research notes

A summary of what informed the design (September 2026).

## Apple Readiness (watchOS 27, Series 12 / Ultra 4 only)

- A 0–10 score that arrives each morning and updates through the day (calories burned, naps,
  daytime heart rate).
- **Inputs** ([Apple Support](https://support.apple.com/guide/watch/readiness-flx4gnzby346/watchos)):
  - *Activity:* active calories, workout effort ratings, training load
  - *Vitals:* overnight heart rate, respiratory rate, wrist temperature, HRV, blood oxygen, plus
    daytime heart rate, all compared with a recent baseline that needs **at least 7 of the past 49
    nights** of wear
  - *Sleep:* recent Sleep Score
- **Bands:** Recover 0–1 · Pace Yourself 2–4 · Ready 5–7 · Go For It 8–10.
- **Not published:** weights, how long the baseline takes, and what happens when an input is missing.
- **Why it's limited to Series 12:** the new Health Sensing System samples heart rate every 5 s and
  HRV every 5 min, and introduces separate "Recovery HRV" and "Overall HRV". Older watches record HRV
  only a few times a night.
- **Training Load** (watchOS 11+) compares the intensity × duration of the last 7 days with the
  previous 28 days, using workout effort ratings.

## Oura Readiness (0–100)

Contributors: previous night's sleep, sleep balance (2 weeks), previous-day activity, activity
balance, resting HR, HRV balance (14-day weighted average vs about 2–3 months), body temperature,
recovery index (how early in the night HR bottoms out), and sleep regularity. "Balance"
contributors weight the most recent 2–5 days more heavily.

## Whoop Recovery (0–100 %)

HRV (ln RMSSD, measured during the deepest sleep), resting HR, respiratory rate, sleep performance,
plus skin temperature and SpO₂ on newer straps. All are compared with a rolling baseline of about
14–30 days.

## Garmin Training Readiness (0–100)

Sleep score (last night), recovery time, HRV status (7-day average vs a personal baseline range),
acute load, sleep history (3 nights), and stress history (3 days). Its bands are Poor, Low, Moderate,
High and Prime. Garmin also lets one poor factor dominate the result.

## What older Apple Watches expose via HealthKit

- **Available:** SDNN HRV (not RMSSD), heart rate, resting HR, sleep stages (watchOS 9+),
  respiratory rate, sleeping wrist temperature (Series 8+), SpO₂ (Series 6+), workouts, effort scores
  (watchOS 11+), active energy, and beat-to-beat heartbeat series for HRV readings.
- **Not available:** Apple's Sleep Score, Training Load value, Vitals app outlier flags, and
  Readiness itself.

## Design decisions that follow

1. **Personal baselines over population norms.** Every product above does this.
2. **Robust statistics** (median/MAD) because wrist data is noisy.
3. **Log-scaled HRV** with a 7-day blend to offset SDNN's noise and older watches' sparse readings.
4. **Compute our own sleep score** using Apple's published structure (duration, bedtime, interruptions).
5. **Session-RPE load** with effort from Apple's rating when present, so the load model matches
   Apple's Training Load inputs.
6. **Same 0–10 bands as Apple**, so the numbers are familiar.
7. **Limiting-factor cap** (Garmin/Whoop behaviour) so illness isn't averaged away.
8. **Show the working.** None of the commercial products publish their weights. Transparency is the
   main reason to use this one.
