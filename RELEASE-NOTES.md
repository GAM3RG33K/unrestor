# Release notes

## Unreleased

- In-app updates: a daily check of GitHub's release page (optional), then
  **Download & Install** with a checksum and app verification, a safe swap, and
  automatic restart.
- A countdown in the menu and menu bar while awake under a time limit.
- The Unrestor icon: an open eye with a crescent-moon pupil.
- The app offers to update an older background service to match.

## 0.1.0

First release.

- `unrestor run`, `watch`, `hold`, `status`, `install`, `uninstall`.
- Menu-bar app with a keep-awake switch, timed holds, and limits.
- Root background service with crash-safe restore of the sleep setting.
- Battery floor (never below 10%), heat limit, power-only, optional Low Power
  Mode, all enforced by the service.
- No Apple Developer account needed: ad-hoc signed DMG, Homebrew cask, or build
  from source.
