# Contributing to Kettle

Thanks for helping. Kettle is small on purpose, so the bar for new features is "does it fit in the menubar and the memory budget?"

## Before you start

- Read [DEVELOPMENT.md](DEVELOPMENT.md) for setup and the everyday loop, and [SPEC.md](SPEC.md) for the design.
- For anything bigger than a bug fix, open an issue first so we can agree on the approach.
- New runtime dependencies need an issue and a discussion first. Kettle currently has none.

## Hard rules

- **No network code.** `make lint` fails if networking APIs appear in `Sources/`.
- **No telemetry, analytics or crash reporting**, even opt-out.
- **Stay within the memory and energy budget** (SPEC.md section 8). Run `make memcheck` for any change to the app target, timers, storage or stats.
- **Logic goes in KettleCore, with tests.** Keep the app target thin.
- **Never use real user data** while developing. Use `make dev`, which has its own data folder.

## Pull requests

1. Run `make format`, `make lint` and `make test` before pushing. CI runs the same checks.
2. Keep PRs focused, and describe what changed and how you tested it.
3. If you make a design decision the spec doesn't cover, add a short entry to [docs/DECISIONS.md](docs/DECISIONS.md).

By contributing you agree that your contributions are licensed under the MIT License.
