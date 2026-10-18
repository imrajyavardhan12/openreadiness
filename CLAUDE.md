# OpenReadiness

An open-source, on-device readiness score and health-data explorer for iPhone and Apple Watch (iOS 17+,
watchOS 10+), built from HealthKit data older watches already record. Swift 6 with strict concurrency, SwiftUI,
XcodeGen project.
How to contribute (where code goes, changing the algorithm, privacy): @CONTRIBUTING.md
Read `docs/ARCHITECTURE.md` before changing data flow and `docs/ALGORITHM.md` before touching the score.

## Checks

The Xcode project is generated and gitignored: run `xcodegen generate` after adding or removing files.
Export `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if `xcode-select` points at the Command Line Tools.

```bash
(cd Packages/ReadinessKit && swift test)        # engine and insights, seconds, no Simulator
xcodegen generate && xcodebuild build -project OpenReadiness.xcodeproj -scheme OpenReadiness \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet
                                                # app, watch app and widgets compile (what CI builds)
xcodebuild test -project OpenReadiness.xcodeproj -scheme OpenReadiness \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'          # UI walk + screenshots
xcodebuild test -project OpenReadiness.xcodeproj -scheme OpenReadinessWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)'
```

## Proving a change works

- Scoring and insights logic: a `swift test` case in `ReadinessKit` that fails without the change. Quote the
  result line.
- App, watch or widget code: the build above must pass; package tests don't compile the app targets.
- UI: the UI tests walk every main screen with the `-demo` sample data and attach screenshots. Run the matching
  scheme and look at the screenshots before saying a screen looks right. They're also the README screenshots in
  `docs/screenshots/`.
- Algorithm changes: before/after score distribution and median on `DemoDataSource`, as CONTRIBUTING.md asks.
- VoiceOver labels and Dynamic Type are part of done for any UI change. Colour is never the only cue.
- Never commit health exports, or screenshots taken with real data (`UITEST_USE_STORED_DATA=1`).
