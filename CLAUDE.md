# Kettle

Minimalist, open-source macOS menubar day planner. SPEC.md is the source of truth. Read it before starting any task.

## Hard rules
- No network code, no telemetry, no analytics, no crash reporting.
- No third-party runtime dependencies.
- Stay within the memory and energy budget in SPEC.md section 8 (≤ 25 MB idle).
- Never touch real user data. Use `make dev`, which uses the separate dev data folder.

## How to work
- Logic goes in KettleCore with tests. Keep KettleApp thin.
- Before calling a task done: `make lint && make test` must pass.
- For any change to the app target, timers, storage or stats: also run `make memcheck`.
- Commit after each completed step with a clear message.
- Record decisions the spec doesn't cover in docs/DECISIONS.md.
- Don't edit SPEC.md, README.md or DEVELOPMENT.md without asking. Propose the change instead.

## Naming
"Kettle" (capital K) in user-facing text; lowercase `kettle` in repo names, bundle ids, CLI tools and file names.