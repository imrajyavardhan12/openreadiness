# Contributing

Thanks for helping! A few guidelines:

## Development

```bash
brew install xcodegen
xcodegen generate          # re-run after adding/removing files
cd Packages/ReadinessKit && swift test
```

- Scoring logic belongs in `ReadinessCore`, which is pure Swift with no HealthKit or UI imports. Add
  tests for any behaviour change.
- Keep HealthKit code inside `ReadinessHealthKit`.
- The project uses Swift 6 with strict concurrency, so don't silence warnings. Fix them.
- Every UI element needs sensible VoiceOver labels and must work with Dynamic Type. Colour must never
  be the only cue.

## Changing the algorithm

Transparency is the whole point of this project, so algorithm changes should:

1. Explain the rationale in the PR, with references where possible.
2. Update `docs/ALGORITHM.md` and, if user-visible, `MethodologyView`.
3. Include before/after results on the demo dataset (`DemoDataSource`) and, ideally, on your own
   export via `openreadiness-cli` (score distribution and median). Share only aggregates. Never
   commit or attach an export: it contains your complete health history.

## Privacy

Pull requests that add networking, analytics or third-party SDKs won't be accepted. See `PRIVACY.md`.
