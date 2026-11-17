# Contributing

**Short version:** Unrestor is open source, but this repository is not open for
contributions. Outside pull requests are rejected. Issues are welcome, with no
guarantee. Forking is encouraged.

## Why

Unrestor is a personal project. I built it for myself, I use it every day, and I
chose to open the source so anyone can read it, learn from it, and run it. I
want to keep the code, the workflow, and the small decisions my own, and to keep
the root background service small enough to audit in one sitting. Accepting
outside changes would work against both.

This isn't a comment on you or your code. A pull request can be excellent and
still not fit a project someone keeps personal on purpose.

## Pull requests

- **They will be rejected.** I close outside pull requests without review, with
  no discussion and no exceptions.
- Please don't open one to "start a conversation". Open an issue instead.

## Issues are welcome

- **Bug reports** are the most useful thing you can send. Include your Unrestor
  version, macOS version, Mac model, and the output of `unrestor status` and
  `pmset -g | grep SleepDisabled`.
- **Ideas and feature requests** are read too.
- **No guarantee.** I can't promise that any issue will be answered, fixed, or
  built, or give a timeline. I may close issues that don't fit the project.
- **Security problems** go through private reporting. See
  [SECURITY.md](SECURITY.md) and don't post exploit details in a public issue.

## Fork it

The Apache-2.0 license lets you use, change, and redistribute the code,
commercially or not. If you ship a fork:

- Give it its own name and icon so nobody confuses it with this project, and
  keep the [NOTICE](NOTICE) and [LICENSE](LICENSE) text.
- Change the bundle id (`app.unrestor`), the daemon label and paths, and the
  update feed in `Sources/UnrestorCore/ReleaseFeed.swift`, so your build never
  talks to this project's releases or service.

### Ground rules worth keeping

They keep the root service safe, and they are the rules I follow:

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

`swift test` covers the policy, the protocol, the updater logic, and the daemon
over a real Unix socket as a normal user. It does not cover
`sudo unrestor install`, the launchd job, or the menu-bar UI; see the manual
checks in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Testing the updater

Build a copy with an older `UnrestorVersion.current`, put it somewhere
writable, and run `open -n Unrestor.app --args --update-now`. It checks GitHub,
downloads and verifies the latest release, replaces itself, and relaunches. A
Homebrew install opens Terminal instead, and runs Homebrew's upgrade.

## Icons

Every icon comes from one definition in `scripts/build-icons.py` (an open eye
with a crescent-moon pupil). After changing it, run
`python3 scripts/build-icons.py` (needs `brew install librsvg`) and commit the
regenerated files in `assets/icon` and `site`. Building the app doesn't need it.
