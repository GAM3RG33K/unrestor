# Contributing

Unrestor is deliberately small. Changes that keep it small and safe are the
easiest to accept.

## Ground rules

- The root daemon's surface stays tiny: fixed `pmset` calls, never an
  arbitrary command runner, and never a setting a client can use to weaken the
  safety limits.
- A hold must be released on every exit path. If you add a way to hold, add a
  test that proves it releases.
- Logic goes in `UnrestorCore` or `UnrestorDaemonCore` as pure, testable code.
  `UnrestorApp`, `unrestor-daemon`, and `unrestor` stay thin.

## Build and test

```sh
swift build
swift test
scripts/make-app.sh      # builds dist/Unrestor.app and a DMG
```

`swift test` covers the policy, the protocol, and the daemon over a real Unix
socket as a normal user. It does not cover `sudo unrestor install`, the launchd
job, or the menu-bar UI; see the manual checks in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Pull requests

Describe what changed and why. Keep them small. Do not include credentials.
