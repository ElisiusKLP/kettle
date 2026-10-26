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
