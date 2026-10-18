# OpenReadiness

On-device readiness score and health-data explorer for iPhone and Apple Watch (iOS 17+, watchOS 10+), built from
HealthKit data older watches already record. Swift 6 strict concurrency, SwiftUI, XcodeGen. Read
`docs/ARCHITECTURE.md` before changing data flow, and `docs/ALGORITHM.md` before touching the score.

## Commands

The Xcode project is generated and gitignored: run `xcodegen generate` after adding or removing files. Export
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when `xcode-select` points at the Command Line Tools.

```bash
(cd Packages/ReadinessKit && swift test)        # engine and insights, seconds, no Simulator
xcodegen generate && xcodebuild build -project OpenReadiness.xcodeproj -scheme OpenReadiness \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet
xcodebuild test -project OpenReadiness.xcodeproj -scheme OpenReadiness \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
xcodebuild test -project OpenReadiness.xcodeproj -scheme OpenReadinessWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)'
```

## Verify before you say done

- Scoring or insights logic: a `swift test` case that fails without the change. Quote the result line.
- App, watch or widget code: the `xcodebuild build` above (what CI runs). Package tests don't compile app targets.
- UI: the UI-test schemes walk every main screen with `-demo` sample data and attach screenshots. Run the matching
  scheme and look at them. They also feed `docs/screenshots/`.
- Algorithm change: before/after score distribution and median on `DemoDataSource`, plus `docs/ALGORITHM.md` and,
  if user-visible, `MethodologyView`.
- UI work isn't done without VoiceOver labels and Dynamic Type support; colour is never the only cue.

## Rules

- `ReadinessCore` is pure Swift: no HealthKit or UI imports. HealthKit code stays in `ReadinessHealthKit`.
- Swift 6 strict concurrency: fix warnings, don't silence them.
- No networking, analytics or third-party SDKs (`PRIVACY.md`).
- Never commit a Health export or screenshots taken with real data (`UITEST_USE_STORED_DATA=1`). Share aggregates only.
