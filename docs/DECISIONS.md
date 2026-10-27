# Decisions

Choices the spec doesn't cover, one entry each: what was chosen and why. Newest last.

## Step 1: Scaffold

### Swift Testing instead of XCTest
**Chose:** write all tests with Swift Testing (`import Testing`, `@Test`, `#expect`).
**Why:** the Xcode Command Line Tools ship Swift Testing but not XCTest, so XCTest tests can't build on a CLT-only machine. Swift Testing works with both CLT and full Xcode 16+. As a result the effective toolchain minimum is Swift 6.0 (Xcode 16), even though the package stays on `swift-tools-version: 5.10` and Swift 5 language mode.

### `make test` adds the CLT framework path
**Chose:** when `xcode-select -p` is the Command Line Tools, the Makefile passes `-F` and `-rpath` for `CommandLineTools/Library/Developer/Frameworks` to `swift test`.
**Why:** CLT installs `Testing.framework` outside SwiftPM's default search path. Setting the flags in `Package.swift` (`unsafeFlags`) compiles the tests, but SwiftPM then silently runs zero tests, because it only detects Swift Testing from command-line flags. With full Xcode no flags are added.

### CI selects Xcode 16 on the macos-14 runner
**Chose:** `ci.yml` keeps `macos-14` and switches to the newest installed `Xcode_16*.app` before building.
**Why:** Swift Testing needs the Swift 6 toolchain, and the runner's default Xcode 15.x doesn't have it.

### Dev bundle is not sandboxed
**Chose:** `Kettle Dev.app` is ad-hoc signed without entitlements. Its data lives in `~/Library/Application Support/Kettle-Dev/`. The release `Kettle.app` is sandboxed with `Kettle.entitlements`.
**Why:** a sandboxed dev app could only use its container. `KETTLE_DATA_DIR=/tmp/...` would then be blocked by the sandbox, and `make seed` / `make reset-dev` would have to reach into another app's container, which triggers macOS's "access data from other apps" prompt. The dev data folder can never coincide with the release container, so real data stays untouched.

### Placeholder app shell in step 1
**Chose:** `main.swift` shows a plain-text status item ("Kettle Dev") with a Quit menu until step 7.
**Why:** an accessory app with nothing in the menubar can't be quit without `kill`, and a placeholder lets `make dev` be checked end to end from step 1.

### Not-yet-built make targets fail loudly
**Chose:** `icons`, `appicon`, `seed`, `memcheck` and `profile` exist from step 1 but exit non-zero with the build step they land in.
**Why:** this keeps the full §10 command surface visible without pretending the targets work.

### `make coverage` enforces the 85% target
**Chose:** `scripts/coverage.sh` prints the `llvm-cov` report for `Sources/KettleCore` and exits non-zero below 85% line coverage.
**Why:** the spec states 85% as a requirement, and enforcing it makes it checkable. CI doesn't run it, to keep CI identical to the spec (`lint` + `test`).

### No-network check also guards dependencies and entitlements
**Chose:** `check-no-network.sh` also fails on any `.package(` in `Package.swift` and on `network.client/server` in `Resources/`.
**Why:** "no third-party runtime dependencies" and "no network entitlements" are hard rules, so they get a mechanical check too.

### Release build flags
**Chose:** `swift build -c release -Xswiftc -Osize`, then `strip -x` on the bundled binary and an ad-hoc signature with hardened runtime.
**Why:** SwiftPM release builds already use whole-module optimisation. `strip -x` drops local symbols and keeps what the dynamic linker needs.

### Licence holder
**Chose:** "Copyright (c) 2026 Kettle contributors".
**Why:** the spec doesn't name a holder, and this is the usual choice for community projects. It's easy to change.

### `make test FILTER=…` and test naming
**Chose:** `make test` takes an optional `FILTER` (passed to `swift test --filter`), and DEVELOPMENT.md uses it instead of bare `swift test --filter`. Test functions follow the Swift Testing style, without a `test` prefix (`SteamLevelTests/stepBoundaries`).
**Why:** a bare `swift test` runs zero tests on a CLT-only machine (see above), and Swift Testing identifies tests by their `@Test` attribute, not by name.

## Step 2: Models, Clock and JSONStore

### Extra `PlanTask` fields
**Chose:** in addition to the spec's fields, `PlanTask` has `extendedMinutes` (added by Keep brewing), `brewedSeconds` (time from closed sessions) and `brewingSince` (start of the open session while brewing). `plannedMinutes` stays the original estimate, and the block lasts `plannedMinutes + extendedMinutes`.
**Why:** planned vs. actual stats need the untouched estimate. Remaining time across pause/resume and app relaunches needs the time already brewed. Keeping it on the task, in today's plan, avoids reading the month's raw sessions, which §7 keeps out of memory.

### File format
**Chose:** each file is one JSON object with `schemaVersion` alongside its fields: `labels.json` is `{"labels": [...]}`, `sessions/yyyy-MM.json` is `{"sessions": [...]}`, and plans and settings are the model's own keys. Output is pretty-printed, sorted by key, uses ISO 8601 dates (`2026-10-26T08:00:00Z`), and ends with a newline. Dates and times use `yyyy-MM-dd` and `HH:mm` strings.
**Why:** sorted keys and one value per line keep diffs small. ISO dates are readable. A top-level object leaves room for `schemaVersion` in every file.

### Migrations work on raw JSON
**Chose:** `Migrator` reads `schemaVersion`, decodes directly when it's current, and otherwise upgrades the raw `[String: Any]` object one step at a time (`n` → `n + 1`) before decoding. A file with no `schemaVersion`, or with a newer one than the app knows, is refused. Every kind starts at version 1, with no steps yet.
**Why:** old schemas don't need to be kept as Swift types. Refusing newer files keeps an older Kettle from silently discarding fields it doesn't understand.

### Unreadable files are never overwritten
**Chose:** if a file exists but fails to load (corrupt, newer schema, missing version), `JSONStore` remembers the path and refuses to save over it. It reports `StoreError.writeBlocked` through `onWriteError` until the file loads successfully again.
**Why:** otherwise the app would replace a damaged or newer-format file with defaults, losing the user's data.

### Settings decode leniently
**Chose:** missing or invalid keys in `settings.json` fall back to their defaults instead of failing the whole file. Other files decode strictly, apart from optional or new `PlanTask` fields.
**Why:** settings are low-stakes and often hand-edited. Plans, labels and sessions are user data, so it's better to refuse a bad file than to guess.

### `JSONStore` dependencies are injected
**Chose:** `JSONStore` takes a `FileSystem` (default: temp file + POSIX `rename`), a `WriteScheduler` (default: main queue) and a `Calendar`. It must be used from the main thread. Saves made within 500 ms are combined into one write per file, and a manual `flush()` cancels the pending scheduled one. A failed write stays pending and is retried on the next flush.
**Why:** tests can then check which files startup reads and control the debounce without waiting, and the app gets a single, simple threading rule.

### Sessions file by local start day
**Chose:** a session goes into the `sessions/yyyy-MM.json` file for the month of its start, in the store's calendar (the user's time zone).
**Why:** that matches what the user sees as "the day it happened". Stats split sessions that cross midnight separately (§5.3).

### `LocalDate` uses integer day numbers
**Chose:** `LocalDate` stores year/month/day and does day arithmetic with integer day numbers since 1970-01-01 (Hinnant's algorithms). `Calendar` is used only to convert to and from `Date`.
**Why:** this avoids allocations and DST surprises, and makes week and month ranges in stats cheap.

### Fixtures are read via `#filePath`
**Chose:** `Tests/Fixtures/data/` is a complete sample data folder. Tests locate it relative to `#filePath` instead of declaring SwiftPM resources. One test checks that the store re-writes every fixture byte for byte.
**Why:** it keeps the spec's `Tests/Fixtures/` location (SwiftPM resources must live inside a target folder), and the byte-for-byte test pins the on-disk format.

### CLT: cross-import overlays disabled for tests
**Chose:** on CLT, `make test` also passes `-disable-cross-import-overlays`.
**Why:** CLT ships `_Testing_Foundation.framework` without its Swift module, so any test file that imports both Testing and Foundation fails to compile. The overlay only adds Foundation-specific extras to Swift Testing that we don't use. With full Xcode the flag isn't passed.

## Step 3: QuickAddParser and PlanEngine

### Quick add: where the duration and label go
**Chose:** the duration must be the **last word** once the label is removed (`Write report 45m #work` and `Write report #work 45m` both work). A label is `#` followed by a letter, then letters, digits, `-` or `_`. If there are several, the last one is the label and the rest stay in the title. Units are case-insensitive, `1h30` means 90 minutes, and whitespace is collapsed.
**Why:** this lets "Read 2 chapters" keep its number, and "Review PR #42 #work" keep `#42` in the title. The catch is that a title ending in a bare number, like "Call 911", reads as a duration; adding an explicit duration fixes it ("Call 911 5m").

### Quick add: default duration and invalid input
**Chose:** without a duration the task gets 30 minutes. Durations outside 1...720 minutes, including zero and numbers too big for `Int`, throw `durationOutOfRange`. A line with no title left throws `emptyTitle`.
**Why:** a default keeps "Emails" one keystroke away. Quietly clamping "Tea 13h" to 12 h would surprise the user, so it's an error the UI can show.

### Quick add: label matching
**Chose:** label names match existing labels ignoring case. Quick-adding an archived label unarchives it. A new label gets the first unused colour from an 8-colour palette (`Label.palette`).
**Why:** `#Work` and `#work` should be the same thing, and typing an archived label shows the user wants it back.

### Derived times are live for today
**Chose:** `PlanEngine.schedule` lays blocks out from an anchor: `startTime` if set, otherwise now for today, otherwise no times. Done blocks take their actual brewed time and skipped blocks take none. With `now` supplied (today's plan), the brewing or paused block ends at now + remaining (or now, in overtime), and pending blocks never start in the past.
**Why:** finishing early, pausing or falling behind then moves the rest of the day automatically, so the times shown are always reachable. The timer (step 4) will set `startTime` the first time Start is pressed on a day without one, as §4 describes.

### Reorder, resize and carry-over
**Chose:** `move(fromOffsets:toOffset:)` follows SwiftUI's `onMove` semantics. The stepper and scroll step is 5 minutes, clamped to 1...720. Carry-over moves pending and paused tasks (paused ones become pending and keep their brewed time) to the **end** of today. A task still brewing stays where it is.
**Why:** matching `onMove` makes the popover's drag-to-reorder trivial. Appending never disturbs a day the user has already ordered. A brewing task belongs to the timer.

## Step 4: TimerEngine and SteamLevel

### `TimerEngine` is a value type that returns closed sessions
**Chose:** `TimerEngine` is a struct holding today's plan, the settings, the clock and the calendar. Actions (`start`, `pause`, `toggle`, `done`, `skip`, `keepBrewing`, `editPlan`) mutate it and return any `Session`s they closed, for the caller to append to the store and the stats cache.
**Why:** there are no callbacks or shared state to get wrong, and every behaviour is a plain function of the inputs and the fake clock.

### One active task at a time
**Chose:** at most one task is brewing or paused. Starting another task closes the open session and returns the active task to *pending*, keeping its brewed time. Plain Start (`Space`) resumes the paused task if there is one, otherwise starts the first pending task. When a plan loads, it's repaired: a "brewing" task with no `brewingSince` becomes paused, and any later active tasks become pending.
**Why:** one active task keeps the menubar unambiguous ("the" brewing task, §5.2), and repairing on load keeps hand-edited files from confusing the timer.

### Skip, Done and auto-start
**Chose:** Skip discards the open session; earlier sessions of that task stay recorded. Skip works on the active task or any unfinished task by ID. Only Done auto-starts the next task (per §5.2); Skip doesn't.
**Why:** this follows the spec literally. Skipping is usually a "not now", which isn't a cue to start the next block.

### Keep brewing in overtime covers the overtime
**Chose:** Keep brewing adds `minutes` plus the whole minutes already overdue, so the block runs about `minutes` more from now. Both count as extension minutes, and `plannedMinutes` keeps the original estimate.
**Why:** after an ignored whistle (say 30 minutes overdue), "+10m" taken literally would leave the kettle whistling. Users mean "10 more minutes from now".

### Extension minutes per session survive relaunches
**Chose:** `PlanTask.sessionExtensionMinutes` tracks Keep brewing minutes added during the open session and moves into `Session.extensionsMinutes` when the session closes.
**Why:** the open session lives in today's plan, so a relaunch mid-session must not lose its extension count.

### First Start sets the day's start time
**Chose:** the first Start on today's plan, when it has no `startTime`, sets it to the current hour and minute.
**Why:** §4: "the first block starts at `startTime` (or when the user presses Start)". Storing it keeps derived times stable afterwards.

### Tiny sessions are dropped
**Chose:** sessions shorter than 1 second aren't recorded, and a clock that jumps backwards never adds negative time.
**Why:** an accidental start/pause shouldn't produce noise in `sessions/`, and NTP corrections shouldn't corrupt stats.

### Steam steps and states
**Chose:** a boundary belongs to the lower step (exactly 80% left is step 4, exactly 0% is step 0). "Planned" includes Keep brewing extensions, so after an extension near the end the kettle stays at a low step instead of filling up again. Paused shows the frozen step at 50% alpha. Paused in overtime shows no steam. `IconState.allCases` has 14 states to pre-render: idle, brewing 1–5, paused 0–5, whistling, day complete.
**Why:** this follows §6.2 literally. Whether steam should refill after Keep brewing is a design question for the icon review (step 6).

## Step 5: StatsCalculator and DailyTotalsCache

### Two kinds of figures in `daily-totals.json`
**Chose:** each day/label entry holds:
- *Session figures*: `seconds` of actual brewing (split at local midnight) and `sessions` (counted on their start day). These are **added** as each session closes.
- *Plan figures*: for tasks marked done, `tasksDone`, `plannedMinutes` (original estimate), `doneSeconds` (actual time brewed on them), `tasksExtended` and `extendedMinutes`. These are **recomputed** for the plan's day whenever its plan is recorded.
**Why:** "time per label" should count all real work, including on skipped or unfinished tasks. "Planned vs. actual" is only meaningful for completed tasks. Recomputing plan figures makes them idempotent, so edits, relabelling and repeated saves never double-count. A test checks that incremental updates match a full rebuild over 60 randomised days.

### Seconds, not minutes, in the cache
**Chose:** brewing time is stored as whole seconds.
**Why:** summing per-session minutes would lose up to a minute per session. Seconds are still small integers, and the UI shows minutes.

### Extension stats come from plans
**Chose:** "how often tasks were extended" uses the done tasks' `extendedMinutes` from the plan, not `Session.extensionsMinutes`.
**Why:** a task is either extended or not, whatever the number of sessions, so counting per task is what the stats need. `Session.extensionsMinutes` is still recorded for export.

### Cache file format
**Chose:** `{"days": {"yyyy-MM-dd": {"<label UUID>" or "none": {...}}}, "schemaVersion": 1}`. In memory the keys are `LocalDate` and `UUID?`, and invalid keys make the file unreadable, which protects it from being overwritten.
**Why:** it's readable and diff-friendly, and aggregation does one dictionary lookup per day (a year takes about 1 ms in a debug build).

### Stats rows
**Chose:** rows are sorted by brewing time; ties go by label name, then "No label", then labels that no longer exist (shown as unknown, never dropped). Archived labels appear with their name and colour.
**Why:** this keeps the history intact after archiving or deleting labels (§5.3).

### Week and month ranges
**Chose:** "This week" is the 7 days starting on `weekStartsOn` that contain today. "This month" is the whole calendar month. Weekday maths uses `LocalDate` day numbers.
**Why:** this matches what calendars show, and the ranges include future days, so the chart has a stable width.

### `PerformanceTests` timing and the allocation test
**Chose:** the 20 ms aggregation limit is checked against the fastest of 10 runs, measured with `ContinuousClock`. The "steady-state ticking performs no heap allocations" test comes in step 7, with the menubar tick code it tests.
**Why:** taking the best run avoids flaky failures from scheduler noise. The tick code (countdown formatting and icon-state comparison) doesn't exist until the app shell does.

## Step 6: KettleIcon

### One drawing, many outputs
**Chose:** `KettleDrawing` draws the kettle as CoreGraphics paths in an 18 × 18 unit space (y up), taking separate body and steam colours and an optional rotation. `KettleIcon` wraps it in `NSImage(size:flipped:drawingHandler:)` for the menubar: black template or orange dev. `make appicon` will reuse the same paths at 1024 px.
**Why:** one set of paths keeps the menubar icon and the app icon identical in shape (§6.5), and vector drawing stays sharp at any scale.

### Shape details
**Chose:** a bell-shaped pot outline (1.5 pt stroke, sitting on the baseline), an arched handle, a filled lid knob, and a curved spout ending at (15, 8). The steam is three S-shaped wisps (1.2 pt) above the spout, each a different height. The "outermost" wisp is the rightmost, farthest from the body, and it fades first. Whistling makes each wisp about 12% taller and adds two short lines to the right of the spout. Day complete draws a **check mark** on the body (the spec allowed a heart or a check).
**Why:** a check stays crisp at 18 pt where a heart turns into a blob. Fading the wisp farthest from the kettle first reads as the steam "pulling back".

### Paused dims everything
**Chose:** in the paused state, the whole icon (outline and steam) is drawn at 50% alpha as one transparency layer.
**Why:** the spec dims the outline. Leaving the steam at full strength next to a dimmed kettle looked like a rendering bug, and drawing as one layer stops overlapping strokes from darkening.

### Images are built once, drawn lazily
**Chose:** `KettleIcon.allImages(style:)` builds all 14 `NSImage`s once at launch. Each is vector-backed (drawing handler), and AppKit caches the rasterised result per resolution.
**Why:** this follows §6.1 and §6.4 (no bitmap assets, no redraw on tick). There are 14 states rather than "about 10" because paused keeps its frozen step (0–5).

### Wiggle is a rotation
**Chose:** `image(for:style:rotation:)` rotates the drawing around the middle of the kettle's base. The app (step 11) will show a few pre-built tilted whistling frames once.
**Why:** a few rotated frames are cheap, and nothing animates continuously.

### Preview sheet and pixel tests
**Chose:** `make icons` renders each state on simulated light and dark menubars at 1× and 2×, plus the dev style and 4× nearest-neighbour zooms of the 2× rendering. `KettleIconTests` rasterises at 2× and checks the size, the template flag, black-only pixels, dev orange, steam alpha per step (strictly increasing), no steam in steam-free states, paused at about half alpha with the step frozen, and that all 14 states differ.
**Why:** the preview is for human review, and the pixel tests stop later edits from silently breaking the states.

## Step 7: App shell

### `KettleModel` keeps the app target thin
**Chose:** a `KettleModel` class in KettleCore owns today's `TimerEngine`, labels and settings. After each action it saves the plan, appends closed sessions, updates the stats cache, and switches to the new day when idle. The app only connects it to AppKit.
**Why:** the order of saves and cache updates is logic, so it lives in KettleCore with tests (CLAUDE.md: "Logic goes in KettleCore").

### Ticks align to the countdown, not the wall clock
**Chose:** the single one-shot `DispatchSourceTimer` is re-armed for when the *displayed* value next changes: the next whole second (or minute) of the remaining or overdue time, plus 5 ms. Leeway is 200 ms (seconds mode) or 5 s (minutes mode). When nothing is brewing, the only timer is one at the next local midnight, to switch days. Paused doesn't tick.
**Why:** the block rarely starts on a wall-clock second. Aligning to the countdown's own boundaries changes the title exactly once per second or minute, and never wakes up for nothing. In minutes mode, a steam step can change up to a minute late, which is fine at that precision.

### Sleep and screens off stop ticking
**Chose:** ticking stops on `willSleep` and on `screensDidSleep` (and pending writes are flushed). It resumes, recomputing everything from timestamps, only when both the system and the screens are awake.
**Why:** nobody sees the menubar with the screens off. The whistle notification (step 11) will be scheduled ahead with UserNotifications, so it doesn't depend on ticking.

### Countdown format
**Chose:** in seconds mode, `23:41`, `1:02:03` and in overtime `+00:42`. In minutes mode, `24m`, `1h 05m` and `+3m`. The countdown rounds up and overtime counts up from `+00:00`, capped at 99:59:59. The title uses a monospaced-digit font so it doesn't jitter.
**Why:** the display reaches zero exactly at the whistle, and in minutes mode `h`/`m` avoid confusing `1:05` (hours) with `1:05` (minutes and seconds).

### Zero allocations, checked on optimised code
**Chose:** `steadyStateTickingDoesNotAllocate` counts heap allocations on the test's own thread with libmalloc's `malloc_logger` hook, over 3,000 ticks (every steam step and into overtime). It only runs in optimised builds, via a new `make test-release` (also a CI step, and `make memcheck` will run it). In `make test` it shows as skipped, with the reason.
**Why:** unoptimised code allocates inside unspecialised generic calls, such as the `firstIndex(where:)` closure call. That isn't what ships. The release build allocates 0. The countdown formatter writes ASCII into a ≤15-byte small string with static `inout` helpers, rather than nested functions that box their captures.

### Unbundled runs use the dev folder
**Chose:** with no bundle identifier (e.g. `swift run Kettle`), `DataLocation` uses `Kettle-Dev`.
**Why:** anything that isn't the release bundle is a development run and must never share a folder name with real data.

### Unreadable data stops the app with an explanation
**Chose:** if today's plan, settings or labels can't be read at launch, Kettle shows an alert ("Nothing has been changed…") with Quit and Reveal Data Folder, then quits.
**Why:** running on defaults could later overwrite the user's data. `JSONStore` refuses to overwrite unreadable files anyway, but an app with a silently empty day would be confusing.

### Temporary status menu
**Chose:** until the popover (step 9), clicking the kettle opens a menu with Start/Pause/Resume, Done, Keep brewing, Skip, "Add 2-minute test task" and Quit. The menu is rebuilt only when it opens.
**Why:** it makes `make dev` testable end to end now, and step 8's memcheck needs a running timer.

## Step 8: memcheck

### `make memcheck` measures a throwaway folder, in both precisions
**Chose:** `scripts/memcheck.sh` runs `make test-release` (zero-allocation ticking), builds the release Kettle Dev, seeds `build/memcheck/data` (via `KETTLE_DATA_DIR`) with today's first task already brewing, then launches and measures:
- Footprint: `footprint -f bytes`, falling back to `ps -o rss=`.
- Average CPU: CPU time used over the window ÷ wall time.
- Idle wake-ups: the change in `top`'s cumulative `IDLEW`.

Seconds mode runs twice for 30 s each, after a 10 s settle, and the lower-CPU run counts. Minutes mode runs once for 120 s. The report is saved to `build/memcheck/report.txt`.
**Why:**
- A throwaway folder never touches your dev data.
- Seeding a brewing task avoids UI automation.
- §8 has separate wake-up budgets per precision, so both are measured.
- A 30 s window can't resolve a "≤ 1 per minute" budget.
- CPU readings are noisy right after a build and seeding.

### `make seed` arrives early
**Chose:** `kettle-tools seed [--brewing]` was built in step 8, not 13, because memcheck needs it. It writes deterministic demo data (6 labels, one archived; 14 past days with sessions; today; tomorrow) into the dev folder or `KETTLE_DATA_DIR`, rebuilds the stats cache, and refuses to write into a folder that already has data.
**Why:** memcheck must "seed data" (§10), and refusing to overwrite protects whatever is in the dev folder.

### Seconds-mode CPU budget (resolved below)
**Found:** footprint is well within budget (11–16 MB of 25 MB). But **any visible change to an `NSStatusItem` once a second costs about 0.35–0.45% CPU** in the release build:

| Release build, 20 s windows | CPU |
|---|---|
| Seconds countdown | 0.45% |
| Icon only, timer still ticking every second | 0.05% |
| Swapping two cached images every second, no title | 0.35% |
| Fixed-length item instead of variable length | 0.45% (no change) |
| Updates wrapped in a `CATransaction` with actions disabled | 2.8% (worse) |
| Minutes mode | 0.00% |

Our own tick allocates nothing and is negligible; the cost is AppKit rendering and committing the status item. The §8 budget of < 0.1% average CPU can't be met with a per-second countdown. Under §8 ("it stays out of v1 or becomes opt-in"), a decision is needed. Until then `make memcheck` fails on seconds-mode CPU. Minutes-mode readings were also noisy (0.00% / 0 extra wake-ups in one run; 0.33% / 16 per minute in another), which suggests the menubar sometimes asks every status item to redraw. That needs a measurement on an otherwise idle machine.

### Smart precision is the default
**Chose (with the maintainer, at the step 8 checkpoint):** a new `TimerPrecision.smart`, which is the default. It shows minutes (`24m`) and switches to seconds for the final minute (`00:59`) and the first minute of overtime (`+00:42`). `.seconds` and `.minutes` stay selectable. The tick that enters the final minute gets the fine (200 ms) leeway, so the seconds start on time. SPEC §4, §8 and §10 and the README were updated to match. `make memcheck` enforces the budget for smart mode and reports seconds-mode CPU for information (still checking its wake-ups).
**Why:** a live per-second countdown costs about 0.4% CPU in AppKit rendering alone. Smart keeps the energy use of minutes mode for almost the whole block, and still gives the whistle a live final countdown.

### memcheck judges smart mode on the median of four 60 s slices
**Chose:** smart mode is measured in four consecutive 60 s slices after a 10 s settle. The budget applies to the median slice, the largest slice footprint is reported, and every slice is printed.
**Why:** macOS sometimes does about 2 minutes of work (~0.4% CPU, ~12 wake-ups/min, +5 MB) on a newly launched status item 1–3 minutes after launch. Sampling the app when it didn't happen showed every thread idle. A one-off transient isn't the "all day" steady state that §8 budgets, but printing every slice keeps it visible. The full run takes about 5 minutes.

## Step 9: Popover

### Clicks
**Chose:** left-click toggles the popover. Right-click (or control-click) opens a small menu with Settings… and Stats… (enabled in steps 10 and 12) and Quit Kettle. The menu is built when needed and detached again.
**Why:** the popover is the main surface. Quit has to live somewhere, and an accessory app has no menu bar of its own.

### Popover state is a snapshot, not a live binding
**Chose:** an `@Observable` `PopoverState` (Observation framework, not Combine) is created with the `NSHostingController` when the popover opens, and both are released in `popoverDidClose`. It copies the shown day's plan, labels and settings from `KettleModel`, and reloads after each action.
**Why:** nothing observable or SwiftUI-related exists while the popover is closed (§8 rule 2), and the core stays free of UI frameworks. The only live parts are the derived times (refreshed every minute) and the active row's countdown (every second), both via `TimelineView`, which runs only while the popover is visible.

### Planning other days
**Chose:** ⌘← / ⌘→ switch days. Other days' plans are read from disk on demand, edited through `KettleModel.editPlan(for:)`, saved and dropped. Start, Done and Keep brewing appear only on the timer's day. On other days the footer says "Planning tomorrow" and offers "Back to today". Clicking the date title also returns to today.
**Why:** §5.1 (plan tomorrow tonight) and §7 (only today's plan stays in memory).

### Carry over
**Chose:** "Carry over N" appears in the footer only when today is shown and yesterday has pending or paused tasks.
**Why:** it keeps the footer quiet on most days.

### Row details
**Chose:** each row shows the label colour, the title (struck through if skipped, dimmed if finished), "start–end · label · status", the planned minutes plus extensions, and a stepper (±5 minutes; disabled for finished tasks). Its right-click menu offers Start, Skip and Delete. Drag reorders the list. The popover's countdown always shows seconds.
**Why:** this is what §5.1 asks for. Per-second updates inside an open popover cost nothing while it's closed. A scroll gesture on the duration is left out: the stepper covers resizing and doesn't fight with scrolling the list.

### Shortcuts
**Chose:** ⌘N focuses quick add, ⌘↩ is Done, ⌘E is Keep brewing, ⌘←/⌘→ change day. `Space` for start/pause comes in step 13.
**Why:** `Space` needs care so it doesn't fire while typing in quick add.

### Quick-add errors are shown inline
**Chose:** invalid input keeps the text and shows a one-line hint under the field.
**Why:** the user can fix the input without retyping it.

## Step 10: Settings window

### Import merges; it never deletes
**Chose:** JSON export is one file with `formatVersion`, `exportedAt`, settings, labels, every plan and every session. Import **merges**: labels by ID (the imported version wins), each imported day's plan replaces that day, sessions are added unless their ID already exists, settings are replaced, and the stats cache is rebuilt. A newer `formatVersion` is refused. A confirmation dialog explains this before importing. A test checks that export → import into an empty folder reproduces every file byte for byte.
**Why:** a merge can't lose data, and importing an old backup by mistake is recoverable. "Export and import round-trip without data loss" (§13) is covered by the byte-for-byte test.

### CSV is one row per session
**Chose:** `date,start,end,minutes,label,task,extension_minutes` in local time, RFC 4180 quoting.
**Why:** spreadsheet users mostly want "where did my time go", which is the sessions. Plans are in the JSON export.

### Delete all data
**Chose:** after a critical confirmation, Kettle removes only its own files (`settings.json`, `labels.json`, `plans/`, `sessions/`, `stats/`) and anything pending. It then starts from defaults with an empty today.
**Why:** if the user pointed `KETTLE_DATA_DIR` at a folder that holds other things, those must survive.

### Settings apply immediately
**Chose:** every control writes straight through `KettleModel` (debounced to disk as usual). Changing the menubar format or countdown precision redraws the menubar at once. Labels can be renamed (on Return; empty names are ignored), recoloured with the system colour picker, archived, or added. There's no delete, so stats always have a name to show.
**Why:** this is the usual macOS settings behaviour, and §5.3 asks for archiving, not deleting.

### Launch at login
**Chose:** `SMAppService.mainApp` register/unregister. Failures, or the "needs approval" state, show a one-line hint under the toggle.
**Why:** an ad-hoc signed build may need approval in System Settings → Login Items.

### Window lifetime
**Chose:** the Settings window is created on demand. `isReleasedWhenClosed = false`, and the controller drops its only reference (and the hosting controller) right after `windowWillClose`.
**Why:** under ARC this is the reliable way to free the window and its SwiftUI views on close (§8 rule 2). Letting AppKit release the window while Swift still holds a reference risks a double release.

## Step 11: Notifications and the whistle

### The notification is scheduled ahead
**Chose:** while a task brews, one pending local notification (`io.github.kettle.whistle`) is scheduled with a calendar trigger at the moment the block runs out. It's rescheduled only after actions, settings changes and wake-ups (never per tick), and removed when nothing is brewing. It has actions Done, "Keep brewing +N" and "+M" (titles from Settings). An action only applies if the notification's task is still the active one.
**Why:** a pre-scheduled notification fires on time even while Kettle isn't ticking (screens off, asleep), and a calendar trigger follows wall-clock time across sleep. Checking the task ID stops a stale notification acting on a different task.

### No notifications after the fact
**Chose:** if Kettle starts or wakes when the block is already overdue, it shows the whistling icon but doesn't post a notification or wiggle.
**Why:** a notification about something that ended an hour ago is noise. The menubar already shows `+…`.

### Permission is asked for lazily
**Chose:** Kettle asks for notification permission the first time it has something to schedule (the first Start with "Notify when time's up" on), not at launch.
**Why:** the question then appears in context, and users who never brew are never asked.

### Sound
**Chose:** the notification carries the default notification sound when "Whistle sound" is on. With notifications off but the whistle sound on, Kettle plays the system "Glass" sound itself at zero.
**Why:** this avoids shipping a sound file (no bundled resources) and never plays two sounds at once. A custom kettle-whistle sound could come later.

### Wiggle
**Chose:** when the block first runs out (`MenubarTicker.Update.startedWhistling`), the icon shows five pre-rotated whistling frames 120 ms apart (about 0.6 s), then settles. The frames are rendered the first time a wiggle plays, and nothing plays with Reduce Motion on.
**Why:** this is the single allowed animation (§6.4). It costs a handful of image swaps once per block.

## Step 12: Stats window

### Contents
**Chose:** a segmented picker (Today / This week / This month / Custom with two date pickers), a horizontal bar chart of time per label (annotated with `3h 05m`-style totals), a daily bar chart stacked by label, and a totals table: label (with an "archived" tag), time brewed, planned → actual for done tasks, and "N of M" done tasks extended. Labels use their own colours; "No label" and deleted labels are grey. An empty period says "Nothing brewed in this period yet."
**Why:** this covers §5.3. "Planned → actual" with the extension count is the calibration view §5.3 asks for.

### Data and lifetime
**Chose:** the window reads `daily-totals.json` once, through `KettleModel.loadStats()`, when it opens, and never reads raw sessions. Like Settings, it's created on demand and released after `windowWillClose`, so Swift Charts code only exists while it's open. It opens from the right-click menu or the chart button in the popover footer.
**Why:** §5.3 and §8 rules 2 and 6. The default period is "This week", the most useful view at a glance.

## Step 13: Seed, keyboard and accessibility

### VoiceOver hears the time left, updated per minute
**Chose:** the status item's accessibility label is "Kettle, *task*, brewing|paused, N minutes left" (or "time's up", "N minutes over time", "nothing brewing", "all brewed for today"), built by `StatusDescription` in KettleCore. The app rebuilds it only when the whole-minute value or the icon state changes. In the popover, the active countdown reads as "23 minutes 41 seconds left". Each row's title and details form one element, and the stepper says "Duration of *task*, N minutes".
**Why:** §13 says VoiceOver should describe the remaining time, not the steam. Rebuilding once a minute keeps the per-second tick free of string building.

### Space
**Chose:** in the popover, Space starts, pauses or resumes, except while quick add has focus (so spaces still type) and on days other than the timer's.
**Why:** §5.5, without breaking typing.

### `make seed`
**Chose:** no changes in this step; it was built in step 8 for memcheck.

## Step 14: Re-measure

### `make profile`
**Chose:** `scripts/profile.sh` builds the release Kettle Dev, seeds throwaway data with a task brewing, and records `xctrace --template Allocations` for `PROFILE_SECONDS` (default 60) into `build/traces/`. Without full Xcode it exits with instructions.
**Why:** Instruments only ships with Xcode. The trace window is the time to open and close the popover and Stats so their allocations can be checked.

### Measurements after steps 9–13
**Measured:** release idle footprint 11.9 MB with a task brewing (11 MB at step 7), so the popover, Settings and Stats code costs nothing while closed. `make test-release`: still 0 allocations per tick, and a year of stats aggregates in a few ms.
**Not measured here:** the full `make memcheck` (5 minutes; it kept getting cut off in the agent session) and the popover-open and Stats-open budgets (50 / 70 MB, and back within 3 MB of baseline 10 s after closing), which need someone to click. These are on the pre-release checklist.
