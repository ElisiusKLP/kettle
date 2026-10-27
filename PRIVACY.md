# Privacy

Kettle keeps everything on your Mac. Nothing you type into it ever leaves the device.

- **No network access.** Kettle contains no networking code, and its sandbox entitlements do not include network access, so macOS would block it even if it tried. A check in CI fails the build if networking APIs appear in the source.
- **No telemetry, analytics or crash reporting.** Kettle doesn't measure how you use it and doesn't send reports anywhere.
- **No accounts, update checker or remote config.** New versions are published on GitHub Releases, and you download them yourself.
- **Your data is plain files.** Plans, labels, settings and time statistics are stored as human-readable JSON in Kettle's folder in Application Support. You can open it from **Settings → Data → Reveal in Finder**, export it, or delete it at any time.
- **Logs stay local.** Kettle writes diagnostic messages only to the macOS unified log (`os.Logger`), which never leaves your Mac unless you share it yourself. Kettle writes no log files of its own.
- **Notifications are local.** The whistle notification is scheduled on your Mac through macOS's local notification system. Kettle asks for permission the first time it has a notification to schedule, and works without it.
- **Open at login is optional.** If you turn it on, Kettle registers itself with macOS Login Items (System Settings → General → Login Items), and nothing else.
- **Exports are yours.** Export writes a JSON or CSV file where you choose, and Kettle never reads or sends it anywhere else. Import only reads the file you pick, and merges it into your data without deleting anything.
- **Deleting is complete.** Settings → Data → Delete All Data removes every file Kettle has written in its data folder.

The only file access Kettle has outside its own folder is the file you pick in a save or open dialog (the App Sandbox's "user-selected files" permission).
