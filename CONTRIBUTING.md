# Contributing

Unrestor is deliberately small. Changes that keep it small and safe are the
easiest to accept.

## Ground rules

- The privileged surface stays tiny: named, reversible switches, never an
  arbitrary command runner.
- A hold must be released on every exit path. If you add a way to hold, add a
  test that proves it releases.
- Logic goes in `UnrestorCore` or `UnrestorDaemonCore` as pure, testable code.
  `UnrestorApp`, `UnrestorDaemon`, and `unrestor` stay thin.

## Build and test

```sh
swift build
swift test
```

`swift build` type-checks the app and daemon too. Running them for real needs an
Apple-signed build; see [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Pull requests

Describe what changed and why. Keep them small. Do not include credentials or
signing material anywhere.
