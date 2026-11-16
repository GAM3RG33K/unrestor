# Release notes

## 0.1.0 (unreleased)

First release.

- `unrestor run`, `watch`, `hold`, `status`, `install`, `uninstall`.
- Menu-bar app with a keep-awake switch, timed holds, and limits.
- Root background service with crash-safe restore of the sleep setting.
- Battery floor (never below 10%), heat limit, power-only, optional Low Power
  Mode, all enforced by the service.
- No Apple Developer account needed: ad-hoc signed DMG, Homebrew cask, or build
  from source.
