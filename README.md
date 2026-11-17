<div align="center">

<img src="assets/icon/unrestor-icon.svg" width="128" height="128" alt="Unrestor app icon: an open eye with a crescent moon for a pupil">

# Unrestor

**Close the lid. Your work keeps running.**

A small, free macOS tool that keeps your MacBook awake with the lid shut, for exactly as long as a command, a process, or a timer needs it.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://www.apple.com/macos/)
[![CI](https://github.com/GAM3RG33K/unrestor/actions/workflows/ci.yml/badge.svg)](https://github.com/GAM3RG33K/unrestor/actions/workflows/ci.yml)
[![Pull requests: closed](https://img.shields.io/badge/pull_requests-closed-lightgrey)](CONTRIBUTING.md)
[![Issues: welcome](https://img.shields.io/badge/issues-welcome-brightgreen)](https://github.com/GAM3RG33K/unrestor/issues)

[Download](https://github.com/GAM3RG33K/unrestor/releases/latest) &middot; [Website](https://unrestor.harshjoshi.dev/) &middot; [Install](#install) &middot; [Commands](#commands)

</div>

## A personal project, open to everyone, closed to contributions

Unrestor is something I built for myself and then open-sourced. Everything is
here under Apache-2.0: read it, build it, fork it, change it, ship your own
version.

It is **not open for contributions**. I want to keep the code, the workflow,
and the small details my own, so **pull requests from outside are rejected**,
however good they are. If you want a feature, fork it and make it yours.

**Issues are welcome.** Bug reports and ideas are read. I can't promise that
every one is answered, fixed, or built, and I can't promise a timeline.
Details are in [CONTRIBUTING.md](CONTRIBUTING.md).

## What it does

Start a build, a test run, or an AI agent through `unrestor`, close the
MacBook, and walk away. When the work ends, the Mac is allowed to sleep again.

```sh
unrestor run -- npm run build         # awake only while the build runs
unrestor run --for 2h -- claude       # any tool, capped at two hours
unrestor watch 4821                   # awake while process 4821 runs
unrestor hold --for 90m               # a plain keep-awake with a timer
unrestor status                       # what is holding the Mac awake, and why
```

A menu-bar app does the same with one switch and a countdown.

## Why it exists

A MacBook sleeps when you close the lid unless a charger, an external display,
and a keyboard are all attached. `caffeinate` does not reliably prevent
lid-close sleep. `sudo pmset disablesleep 1` does, but it is global and easy to
forget: a crash, a forgotten `off`, or a reboot can leave a Mac awake and warm
inside a bag.

Unrestor is a careful wrapper around that one switch.

- **It lets go by itself.** A hold lives and dies with the command, process, or
  timer that asked for it. If the command exits, the terminal closes, or the
  connection drops, a background service releases the hold and puts your
  original setting back, even after a crash or reboot.
- **It works on battery.** Lid-closed holds don't need a charger.
- **The limits always win.** The Mac sleeps again when the battery falls below
  a floor you pick (default 20%, never below 10%), when it runs hot, or, if you
  chose power-only, when you unplug it. The background service enforces these
  itself, so a buggy client can't turn them off.
- **It works with anything.** If you can start it from a terminal, you can
  wrap it. No plugins, no per-tool setup.
- **It stays small and local.** No account, no analytics, no tracking. The only
  network request is an optional once-a-day look at this project's public
  release page. Turn that off and the app never goes online.

## The menu-bar app

- A **Keep Mac awake** switch with a live countdown when a time limit is set.
- One-click timers: **30m, 1h, 2h, 4h, 8h**, or no limit.
- A list of the commands and processes currently holding the Mac awake.
- Limits you can change: a battery floor from 10% to 50%, **only while
  connected to power**, and **Low Power Mode while awake**.
- **Launch at login**, and a menu-bar icon that shows whether a hold is active.
- Update checks, with a download, verify, and install flow (see
  [Updates](#updates)).
- A guided one-time setup for the background service.

The command-line tool works without the app running.

## Install

Requires macOS 14 or later.

Unrestor is **not notarized by Apple**, because that needs a paid developer
account. It is ad-hoc signed and built in the open by GitHub Actions, so you can
read the code and check the build. macOS asks you to approve it once.

### Option 1: Homebrew

```sh
brew install --cask GAM3RG33K/tap/unrestor
sudo unrestor install
```

The cask clears the download warning and puts `unrestor` on your PATH.

### Option 2: Download the DMG

1. Download `Unrestor-VERSION.dmg` from the
   [latest release](https://github.com/GAM3RG33K/unrestor/releases/latest) and
   drag **Unrestor** to **Applications**.
2. Open it. macOS says it can't verify the app. Go to **System Settings →
   Privacy & Security**, scroll down, and choose **Open Anyway**. (Or in
   Terminal: `xattr -dr com.apple.quarantine /Applications/Unrestor.app`.)
3. In the menu-bar app, choose **Install Background Service…** and enter your
   password. Or in Terminal:

   ```sh
   sudo /Applications/Unrestor.app/Contents/Helpers/unrestor install
   ```

   To type `unrestor` anywhere afterwards:

   ```sh
   sudo ln -s /Applications/Unrestor.app/Contents/Helpers/unrestor /usr/local/bin/unrestor
   ```

### Option 3: Build from source

```sh
git clone https://github.com/GAM3RG33K/unrestor && cd unrestor
scripts/make-app.sh              # builds dist/Unrestor.app and a DMG
sudo dist/Unrestor.app/Contents/Helpers/unrestor install
```

### Check it works

```sh
unrestor status            # "Background service: running"
unrestor run -- sleep 30   # close the lid; it keeps going
```

## Commands

| Command | What it does |
|---|---|
| `unrestor run [--for TIME] [--name NAME] -- COMMAND` | Awake until COMMAND exits. Its exit code passes through. |
| `unrestor watch PID [--for TIME] [--name NAME]` | Awake while process PID runs. |
| `unrestor hold [--for TIME]` | Awake until Ctrl-C, or until TIME passes. |
| `unrestor status` | Is the service running, and what is holding the Mac awake? |
| `unrestor install` / `uninstall` | Add or remove the background service (needs `sudo`). |
| `unrestor help` / `--version` | The full guide, including troubleshooting. |

TIME looks like `90m`, `2h`, `1h30m`, or `45s`. A bare number means minutes.
Each command stays in the foreground until it is done; add `&` to background
one.

## Troubleshooting

| Problem | Fix |
|---|---|
| "The background service is not running" | `sudo unrestor install` |
| macOS blocks the app from opening | System Settings → Privacy & Security → **Open Anyway** |
| The Mac still sleeps | `unrestor status` names the reason: low battery, heat, power-only, or no service. |
| Check the system setting by hand | `pmset -g \| grep SleepDisabled` (1 means sleep is blocked) |
| Sleep stays blocked after quitting everything | `sudo unrestor uninstall`. If it still reads 1 and you did not set it, `sudo pmset -a disablesleep 0`. |

A closed MacBook in a bag can get warm. The heat limit helps, but don't leave a
hold running in an enclosed space for long.

## Updates

The menu-bar app checks GitHub once a day for a newer release. Turn that off
with **Check for updates automatically**, or press **Check for Updates** any
time.

**Direct installs** update in place. **Download & Install** fetches the DMG
over HTTPS, checks it against the SHA-256 published beside it, verifies the new
app, swaps it in, and restarts Unrestor. A manual hold ends when it restarts;
commands started with `unrestor run` keep running.

**Homebrew installs** update through Homebrew, so Homebrew's record stays
correct. **Download & Install** opens Terminal and runs:

```sh
brew update && brew upgrade --cask GAM3RG33K/tap/unrestor && sudo unrestor install
```

Enter your password in Terminal when it asks. That last step restarts the
background service, which `brew upgrade` removes. You can run the same line
yourself any time.

If the app offers **Update Background Service…**, accept it: it makes the root
service match the new app, and macOS asks for your password.

The check sends nothing about you or your Mac: no version, no id, no cookies.
It is not a signature check. Releases aren't signed by a developer, so the
checksum catches a corrupt download, not a hijacked GitHub account.

## Uninstall

```sh
sudo unrestor uninstall     # stops the service and restores your sleep setting
```

Then delete `Unrestor.app`, or run `brew uninstall --cask unrestor`. Your
settings are in `~/Library/Application Support/Unrestor`.

## How it works

`unrestor` connects to a small background service over a private Unix socket
and renews its hold every second. The service runs as root, changes one system
setting, and records the original so it can restore it after a crash or reboot.
It accepts three text commands, runs no one's code, and only the user who
installed it can talk to it. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for the design and [SECURITY.md](SECURITY.md) for exactly what it can and
can't do.

## Contributing

No pull requests, please: this repository is a personal project and outside
PRs are rejected. Fork it freely. Issues are welcome, with no guarantee of a
reply or a fix. Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

For your own fork:

```sh
swift build && swift test
```

## Credits

Unrestor started from [Let It Brew](https://github.com/ruban-24/letitbrew) by
Ruban (Apache-2.0), and is a separate project with its own name and icon. See
[NOTICE](NOTICE).

## License

Apache License 2.0. See [LICENSE](LICENSE).
