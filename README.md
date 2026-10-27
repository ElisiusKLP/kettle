# Kettle 🫖

**Put your day on the stove, one block at a time.**

Kettle is a minimalist, open-source macOS menubar app. Each morning you line up your day as time blocks. The current block then brews in your menubar: a little kettle with a live countdown, whose steam slowly fades as time runs out. When the time is up, the kettle whistles.

[![CI](https://github.com/OWNER/kettle/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/kettle/actions) · MIT License · No telemetry · ~25 MB RAM

## Features

- **Day planner in your menubar.** Add tasks, set durations, and drag to reorder. Start and end times update automatically.
- **A kettle that cools down.** The menubar shows the kettle and a countdown (`24m`, then `00:59` in the final minute). Steam rises while you work and fades as the block runs out.
- **Whistle and keep brewing.** When time's up you get a notification. Mark the task done, or keep brewing for a few more minutes (amount set in Settings), and the rest of your day shifts along.
- **Labels and stats.** Tag tasks like `#work` or `#health`, then see time per label by day, week, or month, along with planned vs. actual time.
- **Quick add.** Type `Write report 45m #work` and press Return.
- **Featherweight.** Kettle is built to idle at around 25 MB of RAM with near-zero CPU, because it's always running.
- **Private by design.** No network access, no accounts, no analytics. Your data is plain JSON on your Mac.

## Install

Download the latest `Kettle-x.y.z.zip` from [Releases](https://github.com/OWNER/kettle/releases), unzip it, and move **Kettle.app** to Applications. On first launch, right-click the app and choose Open, since the build is not notarized yet.

To build it yourself, see [DEVELOPMENT.md](DEVELOPMENT.md). Requires macOS 14 Sonoma or later.

## Usage

1. Click the kettle in the menubar.
2. Add your tasks for the day, for example `Emails 20m #admin` or `Deep work 1h30m #work`.
3. Press **Space** to start brewing.
4. When the kettle whistles, choose **Done** or **Keep brewing**.

| Shortcut | Action |
|---|---|
| `⌘N` | New task |
| `Space` | Start / pause |
| `⌘↩` | Mark current task done |
| `⌘E` | Keep brewing (extend) |
| `⌘←` / `⌘→` | Previous / next day |

Use **Settings** to set the extend duration, auto-start behaviour, menubar format, timer precision (seconds all the time if you like, at a small energy cost), labels, and data export.

## Your data

Everything lives in a folder you can open from **Settings → Data → Reveal in Finder**. You can export it to JSON or CSV at any time. Kettle has no network permission at all; see [PRIVACY.md](PRIVACY.md).

## Contributing

Issues and PRs are welcome. Start with [DEVELOPMENT.md](DEVELOPMENT.md) and [CONTRIBUTING.md](CONTRIBUTING.md). The full design is in [SPEC.md](SPEC.md).

## License

MIT
