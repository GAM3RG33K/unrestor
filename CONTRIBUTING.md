# Contributing

Unrestor is 100% open source (Apache-2.0) but **not open for contributions**.
It is a small tool kept deliberately narrow, and I maintain it myself. Pull
requests are not accepted and will be closed without review, however good they
are. Nothing personal: it keeps the code small, and it keeps the root background
service easy to audit.

## What you can do instead

- **Fork it.** Apache-2.0 lets you use, change, and redistribute the code,
  commercially or not. Build your own version with the features you want.
- **Rename your fork.** Use your own name and icon so people do not confuse it
  with this project, and keep the [NOTICE](NOTICE) and license text.
- **Report bugs.** Issues describing a bug are welcome and read, with no promise
  of a fix or a timeline. Feature requests are read too, but most will not be built.
- **Report security problems privately.** See [SECURITY.md](SECURITY.md).

## If you fork it

The ground rules below are what keep the root service safe. They are worth
keeping in a fork.

- The root daemon's surface stays tiny: fixed `pmset` calls, never an
  arbitrary command runner, and never a setting a client can use to weaken the
  safety limits.
- A hold must be released on every exit path. If you add a way to hold, add a
  test that proves it releases.
- Logic goes in `UnrestorCore` or `UnrestorDaemonCore` as pure, testable code.
  `UnrestorApp`, `unrestor-daemon`, and `unrestor` stay thin.
- Change the bundle id (`app.unrestor`), the daemon label and paths, and the
  update feed in `Sources/UnrestorCore/ReleaseFeed.swift`, so your build never
  talks to this project's releases or service.

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

## Testing the updater

Build a copy with an older `UnrestorVersion.current`, put it somewhere
writable, and run `open -n Unrestor.app --args --update-now`. It checks GitHub,
downloads and verifies the latest release, replaces itself, and relaunches.

## Icons

Every icon comes from one definition in `scripts/build-icons.py` (an open eye
with a crescent-moon pupil). After changing it, run
`python3 scripts/build-icons.py` (needs `brew install librsvg`) and commit the
regenerated files in `assets/icon` and `site`. Building the app does not need it.
