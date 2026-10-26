# Developing Kettle

This guide gets you from a fresh clone to running tests, a safe dev instance of the app, and memory checks. All commands run from the repository root.

## Requirements

- macOS 14 or later
- Xcode 15.3 or later, or the Xcode Command Line Tools (`xcode-select --install`). Instruments (for `make profile`) needs full Xcode.
- Homebrew (optional, used to install the linters)

## First-time setup (run once, in this order)

```bash
git clone https://github.com/OWNER/kettle.git
cd kettle
make bootstrap      # checks Swift/Xcode, installs SwiftLint + SwiftFormat if missing
make build          # first debug build, which confirms the toolchain works
make test           # all unit tests should pass on a clean clone
```

## Everyday loop

```bash
make format         # 1. auto-format your changes
make lint           # 2. SwiftFormat check, SwiftLint, and the no-network check
make test           # 3. run the unit tests
make dev            # 4. build and launch "Kettle Dev" for manual testing
```

Run steps 1–3 before every commit, since CI runs the same `make lint` and `make test`.

To run a single test suite or test:

```bash
swift test --filter TimerEngineTests
swift test --filter SteamLevelTests/testStepBoundaries
```

To check coverage (the target is at least 85% for KettleCore):

```bash
make coverage
```

## The dev instance

`make dev` builds **Kettle Dev.app** into `build/` and launches it. Its kettle is orange, so you can tell it apart from the real one. It uses:

- bundle id `io.github.kettle.dev`
- its own data folder (`.../Application Support/Kettle-Dev/`)

This means you can run it next to your real Kettle without touching your real data.

For a manual testing session with realistic data:

```bash
make reset-dev      # 1. wipe dev data (asks for confirmation)
make seed           # 2. load two weeks of demo plans, sessions, and labels
make dev            # 3. launch Kettle Dev
make logs           # 4. (optional, in a second terminal) stream the app's logs
```

To point any build at a throwaway folder instead:

```bash
KETTLE_DATA_DIR=/tmp/kettle-scratch make dev
```

## Working on the kettle icon

The menubar icon is drawn in code (`Sources/KettleIcon`), not stored as image files. Its steam fades in six steps as a block runs down, and the kettle whistles at zero (see SPEC.md section 6).

```bash
make icons          # 1. render every state to build/icons/preview.png
open build/icons/preview.png   # 2. review in light and dark, at 1× and 2×
swift test --filter KettleIconTests   # 3. check sizes, template flag, and alpha
make appicon        # 4. only if you changed the shapes: regenerate AppIcon.icns
```

To see the steam fade live without waiting, quick add `Steam test 2m #qa` in the dev app and start it. The steam should change step about every 24 seconds and whistle at 2 minutes.

## Keeping Kettle light

Kettle runs all day, so memory and energy use are treated like failing tests. The budgets are in SPEC.md section 8; the main one is **≤ 25 MB physical footprint when idle**.

Before opening a PR that touches the app target, timers, storage, or stats, run:

```bash
make memcheck       # builds release, seeds data, starts a task, measures, fails if over budget
```

To dig into a regression:

```bash
make profile        # records an Instruments Allocations trace into build/traces/
open build/traces/*.trace
```

You can also check a running instance by hand:

```bash
footprint "Kettle Dev"                         # physical footprint (the budget metric)
top -l 1 -pid $(pgrep -x "Kettle Dev") -stats pid,cpu,mem,idlew
```

When you check by hand, open and close the popover and the stats window a few times. Memory should return to within 3 MB of the idle baseline about 10 seconds after closing.

The usual causes of a regression are views kept alive after closing, timers or Combine pipelines that tick while the popover is closed, redrawing the icon on every tick, and loading more than today's plan into memory. The rules that prevent these are in SPEC.md section 8.

## Manual test checklist

- Quick add `Test 1m #qa`, start it, and wait for the whistle. Try both **Done** and **Keep brewing**.
- Keep brewing a task and check that every later block's start time moves.
- Put the Mac to sleep mid-task, wake it, and confirm the countdown and steam step are still correct.
- Turn on System Settings → Accessibility → Display → Reduce Motion, and confirm the whistle no longer wiggles.
- Open Stats and confirm the seeded labels show up for This week and This month.
- Export to CSV, run `make reset-dev`, import the JSON, and check that nothing was lost.

## Release build

```bash
make memcheck       # 1. must pass
make release        # 2. builds build/Kettle.app and build/Kettle-<version>.zip
```

The release is size-optimised, symbol-stripped, and ad-hoc signed. Notarization is a later step that requires a Developer ID.

## Project structure

- `Sources/KettleCore`: all logic (models, planning, timer, steam levels, stats, storage). It has no UI imports and is fully unit-tested.
- `Sources/KettleIcon`: CoreGraphics drawing of the kettle and its steam states.
- `Sources/KettleApp`: the AppKit status item, plus SwiftUI views created on demand. It should stay thin.
- `Sources/kettle-tools`: the dev-only CLI behind `make icons`, `make appicon`, and `make seed`. It is never shipped.
- `Tests/`: unit, icon, and performance tests. Inject the fake `Clock` and use a temp directory rather than the real clock or disk.
- `scripts/`: bootstrap, bundling, memcheck, and the no-network check.

See [SPEC.md](SPEC.md) for the full design.

## Rules for contributions

- **No network code.** `make lint` fails if networking APIs appear in `Sources/`.
- **No telemetry, analytics, or crash reporting**, even opt-out.
- **Stay within the memory budget.** Run `make memcheck` for any app-side change.
- **No new runtime dependencies** without discussion in an issue first.
- New logic goes in KettleCore, together with tests.

## Clean up

```bash
make clean          # removes .build/ and build/
```
