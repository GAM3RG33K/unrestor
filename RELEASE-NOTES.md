# Release notes

## 0.1.4

- No code changes. Used to verify updating through Homebrew.

## 0.1.3

- Cask uses Homebrew's current `depends_on macos` syntax.
- The background service no longer changes the process-wide umask while binding its socket; it sets a private umask once at startup. This also fixes flaky tests.
- Used to verify the in-app update path from 0.1.2.

## 0.1.2

- The Homebrew cask is now updated automatically by the release workflow.
- The project is open source but not open for contributions; fork it instead.

## 0.1.1

- In-app updates: a daily check of GitHub's release page (optional), then
  **Download & Install** with a checksum and app verification, a safe swap, and
  automatic restart.
- A countdown in the menu and menu bar while awake under a time limit.
- The Unrestor icon: an open eye with a crescent-moon pupil.
- The app offers to update an older background service to match.
- Updates follow only HTTPS redirects that stay on GitHub.

Note: 0.1.0 has no updater, so install 0.1.1 by hand once; later versions update in the app.

## 0.1.0

First release.

- `unrestor run`, `watch`, `hold`, `status`, `install`, `uninstall`.
- Menu-bar app with a keep-awake switch, timed holds, and limits.
- Root background service with crash-safe restore of the sleep setting.
- Battery floor (never below 10%), heat limit, power-only, optional Low Power
  Mode, all enforced by the service.
- No Apple Developer account needed: ad-hoc signed DMG, Homebrew cask, or build
  from source.
