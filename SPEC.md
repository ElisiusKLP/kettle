# Kettle — Build Specification

> This document is the source of truth for building Kettle. It is written so an AI coding agent (e.g. Claude Code) can implement the app end to end. Follow it in order. When something is ambiguous, prefer the simpler and lighter option, and record the decision in `docs/DECISIONS.md`.

## 1. Product summary

Kettle is a minimalist, open-source macOS menubar app for planning your day in **time blocks**. It looks like a stripped-down day view of a calendar but behaves like a to-do list: each block is a task with a duration, and the blocks run back to back.

The menubar shows a small **kettle** with a live countdown. While a task is brewing, steam rises from the spout, and the steam fades away as time runs out. When the block ends, the kettle whistles. Tasks carry a **label** (category), and Kettle tracks how much time is actually spent per label so the user can see long-term statistics.

Principles, in priority order:

1. **Private.** No network access, no telemetry, no accounts, no analytics, no crash reporters. All data stays on disk in a human-readable format.
2. **Light.** Kettle runs all day in the background, so it must use as little RAM and CPU as possible. See section 8 for hard budgets.
3. **Minimal.** One menubar item, one popover, and a settings window. No dock icon.
4. **Open.** MIT-licensed, developed on GitHub, buildable from the command line, with a fully unit-testable core.

## 2. Target platform and stack

| Item | Choice |
|---|---|
| OS | macOS 14 Sonoma or later |
| Language | Swift 6 toolchain (Swift 5 language mode, `swift-tools-version: 5.10`) |
| Menubar | **AppKit** `NSStatusItem` + `NSPopover`. Do not use SwiftUI `MenuBarExtra`, because it keeps its content view alive and gives no control over teardown. |
| Views | SwiftUI, hosted in `NSHostingController` and **created on demand and destroyed on close** |
| Build | Swift Package Manager (no `.xcodeproj` checked in) plus a bundling script that produces a `.app` |
| Persistence | Codable JSON files in Application Support (no database dependency) |
| Notifications | `UserNotifications` (local only) |
| Logging | `os.Logger` only, with no log files |
| Third-party runtime dependencies | **None** |
| Dev tooling (optional) | SwiftLint, SwiftFormat via Homebrew |

The app runs as an accessory app (`LSUIElement = true`), so it has no dock icon.

## 3. Repository layout

```
kettle/
├── Package.swift
├── Makefile
├── README.md
├── DEVELOPMENT.md
├── SPEC.md
├── LICENSE                     # MIT
├── CONTRIBUTING.md
├── PRIVACY.md                  # states plainly: no data leaves the device
├── .github/workflows/ci.yml    # build + test + lint + no-network check
├── .swiftlint.yml
├── .swiftformat
├── Sources/
│   ├── KettleCore/             # pure Swift, no AppKit/SwiftUI imports
│   │   ├── Models/             # PlanTask, Label, DayPlan, Session, Settings
│   │   ├── Engine/             # PlanEngine, TimerEngine, Clock protocol, SteamLevel
│   │   ├── Stats/              # StatsCalculator, DailyTotalsCache
│   │   └── Storage/            # Store protocol, JSONStore, DataLocation, Migrator
│   ├── KettleIcon/             # CoreGraphics drawing of the kettle + steam (AppKit only)
│   ├── KettleApp/              # the app target
│   │   ├── main.swift          # NSApplication setup, accessory policy
│   │   ├── StatusItemController.swift
│   │   ├── PopoverController.swift   # creates/destroys hosting controller
│   │   ├── Popover/            # SwiftUI: day plan list, quick add, controls
│   │   ├── Settings/           # SwiftUI: General, Labels, Data tabs
│   │   ├── Stats/              # SwiftUI + Swift Charts
│   │   └── Support/            # notifications, launch-at-login, hotkeys, power events
│   └── kettle-tools/           # dev-only CLI: render icon previews, build app icon, seed data
├── Tests/
│   ├── KettleCoreTests/        # unit tests, must not touch real disk or clock
│   ├── KettleIconTests/        # renders every icon state, checks size/template/alpha
│   └── Fixtures/               # sample JSON files
├── Resources/
│   ├── Info.plist
│   ├── Info.dev.plist          # dev bundle id and name
│   └── Kettle.entitlements     # sandbox, NO network entitlements
└── scripts/
    ├── bootstrap.sh            # checks toolchain, installs optional linters
    ├── bundle.sh               # wraps the SPM binary into Kettle.app / Kettle Dev.app
    ├── reset-dev.sh            # deletes dev data only
    ├── memcheck.sh             # launches dev app, measures memory, compares to budget
    └── check-no-network.sh     # fails if networking APIs appear in Sources/
```

`kettle-tools` is a development executable and is never shipped inside the app bundle.

## 4. Data model (KettleCore)

All models are `Codable`, `Identifiable`, `Hashable`, and `Sendable`. The task type is named `PlanTask` to avoid clashing with Swift's `Task`.

```swift
struct Label { id: UUID; name: String; colorHex: String; isArchived: Bool }

struct PlanTask {
    id: UUID
    title: String
    labelID: UUID?
    plannedMinutes: Int          // 1...720
    notes: String?
    status: Status               // .pending, .brewing, .paused, .done, .skipped
}

struct DayPlan {
    date: LocalDate              // yyyy-MM-dd, no time zone ambiguity
    tasks: [PlanTask]            // order = execution order
    startTime: LocalTime?        // optional anchor, e.g. 09:00
}

struct Session {                 // one actual stretch of work, used for stats
    id: UUID
    taskID: UUID
    labelID: UUID?
    start: Date
    end: Date
    extensionsMinutes: Int       // total minutes added via Keep brewing
}

struct AppSettings {
    extendMinutes: Int = 10           // the "Keep brewing" amount
    secondaryExtendMinutes: Int = 5
    autoStartNext: Bool = false
    menubarFormat: MenubarFormat = .iconAndTime   // .iconOnly, .iconAndTime, .iconTitleAndTime
    timerPrecision: TimerPrecision = .seconds     // .seconds or .minutes (lower CPU)
    whistleSound: Bool = true
    notifyOnFinish: Bool = true
    launchAtLogin: Bool = false
    weekStartsOn: Weekday = .monday
}
```

Planned start and end times for each block are **derived**, not stored: the first block starts at `startTime` (or when the user presses Start), and each following block starts when the previous one ends. Reordering or resizing a block shifts everything after it.

## 5. Core behaviour

### 5.1 Planning the day

- The popover opens on **Today** and lists the blocks top to bottom, each showing title, label colour, duration, and derived start–end time.
- **Quick add** field at the top accepts shorthand: `Write report 45m #work`, `Gym 1h #health`, `Emails 20`. Parse duration (`m`, `h`, `1h30m`, bare number = minutes) and `#label` (create the label if it doesn't exist).
- Drag to reorder, and use a stepper or scroll on the duration to resize.
- Left/right arrows switch days so the user can plan tomorrow tonight.
- "Carry over unfinished" moves pending tasks from yesterday into today.

### 5.2 Timer

- `TimerEngine` owns the single brewing task. It takes an injected `Clock` protocol so tests control time.
- **Start** marks the first pending task as brewing and opens a `Session`. **Pause** closes the session and **Resume** opens a new one, so stats count only real working time.
- **Done** finishes the task early and moves to the next one (it auto-starts if `autoStartNext` is on).
- **Skip** marks the task skipped without counting time.
- At zero, the kettle **whistles**: Kettle posts a local notification (if enabled) with actions **Done**, **Keep brewing +N min**, and **+M min**, and the menubar shows overtime as `+00:42`. Overtime counts toward stats.
- **Keep brewing** (the extend feature) adds `extendMinutes` from Settings to the brewing task, increments `extensionsMinutes`, and shifts every following block.
- Remaining time is always computed from timestamps, never by decrementing a counter, so it stays correct across sleep and wake.

### 5.3 Labels and statistics

- Settings → **Labels** tab: create, rename, recolour, and archive labels. Archiving keeps historical stats intact.
- **Stats** window: time per label for Today, This week, This month, and a custom range. It shows a horizontal bar chart and a stacked daily bar chart (Swift Charts), plus a totals table.
- It also shows planned vs. actual minutes per label and how often tasks were extended, which helps users calibrate their estimates.
- `StatsCalculator` is pure and splits sessions that cross midnight.
- `DailyTotalsCache` keeps per-day, per-label minute totals in `stats/daily-totals.json`. It is updated incrementally when a session closes, so stats never need to load the full session history. Raw sessions are read only for export or to rebuild the cache.

### 5.4 Settings window

Tabs:

- **General**: extend amounts, auto-start next, menubar format, timer precision, whistle sound, notifications, launch at login (via `SMAppService`).
- **Labels**: as described in 5.3.
- **Data**: shows the data folder path with a "Reveal in Finder" button, plus Export (JSON or CSV), Import (JSON), and "Delete all data" with confirmation.

### 5.5 Keyboard

- An optional global shortcut to open the popover (default off).
- Inside the popover: `⌘N` new task, `Space` start/pause, `⌘↩` done, `⌘E` keep brewing, `⌘←` and `⌘→` change day.

### 5.6 Voice and theme

Kettle's tea-and-kettle theme lives in a few words and the icon. The UI stays plain and clear; don't overdo it.

| Concept | Copy |
|---|---|
| Active task | "Brewing" |
| Extend button | "Keep brewing +10m" |
| Time's up notification | "Whistle! *Write report* is done." |
| Day finished | "All brewed for today." |
| Empty day | "Nothing on the stove. Add your first task." |

## 6. The kettle icon

The icon is the heart of the app's identity and must also be extremely cheap to render.

### 6.1 Drawing

- Draw the icon in code (`KettleIcon` module) using `NSImage(size:flipped:drawingHandler:)` and CoreGraphics paths. Don't use bitmap assets for the menubar. This keeps it sharp at any scale and avoids loading resources.
- Size it at 18×18 pt, as a **template image** (`isTemplate = true`) drawn in black with alpha only, so macOS tints it correctly for light and dark menubars.
- **Kettle body**: a rounded pot shape with a spout angled up to the right, an arched handle over the top, and a small lid knob. Use a 1.5 pt stroke, an outline style, and sit it on the baseline.
- **Steam**: three soft S-shaped wisps rising from above the spout, each slightly different in height.

### 6.2 Steam level

`SteamLevel` lives in KettleCore so it can be tested. It maps `remaining / planned` to one of **six discrete steps**:

| Step | Remaining | Steam |
|---|---|---|
| 5 | > 80% | three tall wisps, full opacity |
| 4 | 60–80% | three wisps, the outer one shorter and at 70% opacity |
| 3 | 40–60% | two wisps |
| 2 | 20–40% | two short wisps, the second at 50% opacity |
| 1 | 0–20% | one faint, short wisp at 40% opacity |
| 0 | 0% / idle | no steam |

The steam fades by shrinking the wisps and lowering their alpha, starting with the outermost one, so the kettle visibly "cools" as the block runs down.

### 6.3 States

| State | Icon |
|---|---|
| Idle (nothing brewing) | Kettle outline, no steam |
| Brewing | Kettle with steam at the current step |
| Paused | Kettle outline at 50% alpha, steam frozen at its current step |
| Whistling (overtime) | Kettle with a **full burst of steam** and two short "whistle" lines beside the spout. When the block first hits zero, play one short wiggle animation (≤ 1 s). Skip the animation if *Reduce Motion* is on. |
| Day complete | Kettle with no steam and a small filled heart or check on the body |

### 6.4 Performance rules for the icon

- Pre-render all states at launch, about 10 small `NSImage`s, and cache them in a dictionary. Never redraw on each tick.
- Swap `statusItem.button.image` **only when the step or state changes**. That is at most about 6 swaps per block.
- No continuous animation of any kind. The only animation is the single whistle wiggle.

### 6.5 Dev build and app icon

- In Dev builds, use a non-template orange tint so the dev kettle is easy to tell apart from the real one.
- The full-colour app icon (shown in Finder and the Settings window) uses the same paths at 1024 px: a warm copper or teal kettle on a soft cream rounded square, with white steam. `kettle-tools appicon` renders it and builds `AppIcon.icns` via `iconutil`. The result is committed to `Resources/`.

## 7. Storage

- Default location: `~/Library/Containers/<bundle-id>/Data/Library/Application Support/Kettle/` (sandboxed).
- Files: `labels.json`, `settings.json`, `plans/yyyy-MM-dd.json`, `sessions/yyyy-MM.json`, and `stats/daily-totals.json`. These are human-readable and diff-friendly.
- At runtime, keep in memory **only** the settings, labels, today's plan, and the current open session. Load other days only when the user navigates to them, and drop them again on navigation.
- `DataLocation` resolves the folder in this priority order: the `KETTLE_DATA_DIR` environment variable, then the dev bundle (which uses a `Kettle-Dev` folder name), then the default.
- Writes are atomic (write to a temp file, then replace) and debounced to about 500 ms.
- Every file carries a `schemaVersion`, and a `Migrator` upgrades older versions.

## 8. Memory and energy budget (hard requirements)

Kettle sits in the background all day, so being light is a feature. These budgets are measured with `make memcheck` on a release build with `make seed` data. Physical footprint is as reported by `footprint`.

| Situation | Budget |
|---|---|
| Idle in the menubar, popover closed, task brewing | **≤ 25 MB** physical footprint |
| Popover open | ≤ 50 MB |
| Stats window open | ≤ 70 MB |
| 10 s after closing the popover or stats window | back within 3 MB of the idle baseline |
| Average CPU while brewing, popover closed | < 0.1% |
| Idle wake-ups | ≤ 1 per second in seconds mode, ≤ 1 per minute in minutes mode |

To meet them:

1. **Use `NSStatusItem` instead of `MenuBarExtra`.** The menubar shows only an image and a short title string. No SwiftUI views live in the menubar.
2. **Create views on demand and release them.** Create the popover's `NSHostingController` when the popover opens, and set it to `nil` in `popoverDidClose`. The Settings and Stats windows are created on demand and released on close (`isReleasedWhenClosed`, with no strong references kept). Swift Charts code only runs inside the Stats window.
3. **Use one cheap timer.** Use a single `DispatchSourceTimer` aligned to the next whole second (or minute), with `leeway` of 200 ms (or 5 s in minutes mode). Don't use per-view timers, and don't use Combine pipelines that tick while the popover is closed.
4. **Write only when something changed.** Set `statusItem.button.title` only when the formatted string differs from the last one, and set the image only when the steam step changes.
5. **Sleep with the Mac.** Listen for `NSWorkspace.screensDidSleepNotification` and `willSleepNotification`, stop ticking, and recompute from timestamps on wake. Don't disable App Nap.
6. **Keep data small.** Follow the in-memory rule in section 7. Stats read `daily-totals.json`, not raw sessions.
7. **No heavy dependencies.** Don't use WebKit, Combine-heavy architectures, or third-party frameworks. Use `os.Logger` with no log retention.
8. **Make the release build lean.** Build with `-c release -Xswiftc -Osize`, strip symbols in the bundled binary, and use whole-module optimisation.

If a feature can't fit these budgets, it stays out of v1 or becomes opt-in, and the trade-off is documented.

## 9. Privacy and openness requirements (hard rules)

1. No networking code anywhere: no `URLSession`, `Network.framework`, sockets, or WebKit. `scripts/check-no-network.sh` greps `Sources/` for these and CI fails if it finds any.
2. The entitlements file enables App Sandbox and does **not** include `com.apple.security.network.client` or `network.server`.
3. No analytics, telemetry, crash reporting, update checker, or remote config. Updates come from GitHub Releases.
4. `PRIVACY.md` states all of the above in plain language.
5. MIT licence, with `CONTRIBUTING.md`, issue and PR templates, and a CI badge in the README.

## 10. Make targets (the agent must implement these exactly)

| Command | Does |
|---|---|
| `make bootstrap` | Checks Xcode CLT and Swift version, and installs SwiftLint and SwiftFormat via Homebrew if they're missing |
| `make build` | `swift build` (debug) |
| `make test` | `swift test --parallel` |
| `make coverage` | Tests with coverage, and prints a summary for KettleCore |
| `make lint` | SwiftFormat lint, SwiftLint, and `check-no-network.sh` |
| `make format` | Applies SwiftFormat |
| `make icons` | Renders every icon state (light and dark menubar, 1× and 2×) into `build/icons/preview.png` for visual review |
| `make appicon` | Regenerates `Resources/AppIcon.icns` from the drawing code |
| `make dev` | Builds debug, bundles `build/Kettle Dev.app` (bundle id `io.github.kettle.dev`, orange icon), and launches it |
| `make seed` | Fills the dev data folder with two weeks of realistic demo data |
| `make reset-dev` | Deletes the dev data folder only (asks for confirmation) |
| `make logs` | Streams `log stream --predicate 'subsystem == "io.github.kettle"'` |
| `make memcheck` | Builds release with the dev bundle id, seeds data, launches the app, starts a task, waits 30 s, then reports physical footprint (`footprint`, falling back to `ps -o rss=`) and CPU, and **fails if over budget** |
| `make profile` | Launches the dev release build under Instruments (`xcrun xctrace record --template 'Allocations'`) and saves a trace to `build/traces/` |
| `make release` | Builds an optimised release, bundles `build/Kettle.app`, ad-hoc signs it, and zips it into `build/Kettle-<version>.zip` |
| `make clean` | Removes `.build/` and `build/` |

## 11. Testing requirements

- KettleCore must have at least 85% line coverage.
- Required test suites:
  - `QuickAddParserTests`: durations, labels, edge cases, and invalid input.
  - `PlanEngineTests`: derived times, reorder, resize, carry-over.
  - `TimerEngineTests`: start, pause, resume, done, skip, keep brewing, overtime, and sleep/wake via a fake clock.
  - `SteamLevelTests`: step boundaries, the paused and overtime states, and that one block causes at most 6 image changes.
  - `StatsCalculatorTests`: aggregation by range and label, midnight splitting, archived labels.
  - `DailyTotalsCacheTests`: incremental updates match a full rebuild.
  - `JSONStoreTests`: round trip, atomic writes, migrations, and confirmation that only today's plan is loaded at startup.
  - `KettleIconTests`: every state renders at 18 pt, is a template image (except in dev), and uses non-empty alpha for its steam step.
  - `PerformanceTests`: aggregating 1 year of daily totals takes < 20 ms (timed with `ContinuousClock`), and steady-state ticking performs no heap allocations.
- Tests use Swift Testing (`import Testing`), which works with both the Command Line Tools and Xcode 16+. XCTest isn't available in the Command Line Tools.
- CI (GitHub Actions, `macos-14` runner) runs `make lint` and `make test` on every push and PR. `make memcheck` runs locally before each release, since it needs a GUI session.

## 12. Build order for the agent

1. Scaffold the package, Makefile, scripts, licence, and CI. Get `make test` green with one placeholder test.
2. Write the KettleCore models, the `Clock` protocol, and `JSONStore` with tests.
3. Build `QuickAddParser` and `PlanEngine` with tests.
4. Build `TimerEngine` and `SteamLevel` with tests.
5. Build `StatsCalculator` and `DailyTotalsCache` with tests.
6. Build `KettleIcon` with the drawing code, `make icons`, and icon tests. Review the preview sheet before moving on.
7. Create the app shell: `NSStatusItem` with the cached icons and countdown, `make dev` working, and the single timer with sleep handling.
8. Write `make memcheck` and confirm the idle budget **now**, before adding more UI.
9. Build the popover, created on demand: day list, quick add, controls, and day switching.
10. Build the Settings window with its three tabs.
11. Add notifications and the whistle state.
12. Build the Stats window with charts, released on close.
13. Add `make seed`, then polish keyboard shortcuts and accessibility (VoiceOver labels describe the remaining time, not the steam).
14. Re-run `make memcheck` and `make profile` and fix any regressions.
15. Finish README, DEVELOPMENT, and PRIVACY docs, run `make appicon`, and build the release.

## 13. Acceptance checklist

- [ ] No dock icon. The menubar kettle shows the countdown, and its steam fades in steps as the block runs down.
- [ ] At zero the kettle whistles: full steam, one short wiggle (none with Reduce Motion), and a notification.
- [ ] Keep brewing uses the value from Settings and shifts later blocks.
- [ ] Stats show correct per-label totals for day, week, and month.
- [ ] Export and import round-trip without data loss.
- [ ] `make memcheck` passes all budgets in section 8.
- [ ] Closing the popover or stats window returns memory to baseline.
- [ ] `make dev` never touches real user data.
- [ ] `make lint && make test` pass on a clean clone after `make bootstrap`.
- [ ] Nothing in the codebase can reach the network.

## 14. Out of scope for v1 (good first issues later)

Calendar (EventKit) import, iCloud or Git sync, recurring task templates, Shortcuts/AppIntents, widgets, localisation, and Pomodoro mode. Each must respect the memory budget.
