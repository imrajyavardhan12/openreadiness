# Privacy

OpenReadiness is built so that your health data never leaves your devices.

- **Read-only HealthKit access.** The app requests read permission only and never writes to Health.
  It reads Apple Watch data in these areas: heart (heart rate, resting and walking HR, HRV,
  heart-rate recovery, cardio fitness), sleep, workouts and effort, activity (steps, energy,
  exercise, stand, distance, flights, rings), respiratory rate, blood oxygen, wrist temperature,
  mobility (walking speed, step length, asymmetry), environment (sound exposure, headphone audio,
  time in daylight) and date of birth (for age-based heart-rate zones).
- **On-device computation.** All scoring runs locally on your iPhone (or Apple Watch).
- **No network.** No servers, accounts, analytics, crash reporting, ads or third-party SDKs. The app
  makes no network requests.
- **Minimal storage.** Raw health data is read from HealthKit into memory each time the app
  refreshes and is never written to disk. What is stored: two preferences (your sleep goal and
  whether sample data is on) and, for widgets and complications, today's score summary. That
  summary is the score, its contributor headlines and the last 7 scores. It lives in the app's
  private App Group container on your device, readable only by OpenReadiness and its own widgets.
  There is also a cache of the HRV (RMSSD) values computed from each overnight heartbeat recording:
  derived numbers only, never raw heartbeats. It is kept in the app's private container with iOS
  file protection and pruned after 200 days.
- **Imported exports stay on the device.** If you import a Health export, the parsed data is saved
  as one file in the app's private container with iOS file protection. It's never uploaded,
  never shown on widgets or the watch, and *About › Remove imported data* deletes it.
- **Export is yours to trigger.** "Export readiness history" and "Export daily health metrics"
  create CSV files only when you tap them, and hand them to the system share sheet. They go only
  where you send them.
- **Watch sync.** The iPhone sends today's score, its contributors and the last 7 scores to your own
  paired Apple Watch through Apple's WatchConnectivity framework.
- **Control.** Change or revoke access at any time in *Settings › Health › Data Access & Devices ›
  OpenReadiness*. Declined data types simply don't contribute to the score.

Because the source is open, every statement above can be checked in the code.
