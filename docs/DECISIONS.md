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
