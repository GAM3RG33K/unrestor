<div align="center">

<img src="assets/icon/unrestor-icon.svg" width="128" height="128" alt="Unrestor app icon: an open eye with a crescent moon for a pupil">

# Unrestor

**Close the lid. Your work keeps running.**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://www.apple.com/macos/)
[![CI](https://github.com/GAM3RG33K/unrestor/actions/workflows/ci.yml/badge.svg)](https://github.com/GAM3RG33K/unrestor/actions/workflows/ci.yml)

[Download](https://github.com/GAM3RG33K/unrestor/releases/latest) &middot; [Website](https://gam3rg33k.github.io/unrestor/)

</div>


A free, open-source, minimal macOS keep-awake tool for long-running commands.
Start a build, a test run, or an AI agent through `unrestor`, shut the MacBook,
and walk away. When the work ends, the Mac sleeps again. A battery floor and a
heat limit always win.

```sh
unrestor run -- npm run build         # awake only while the build runs
unrestor run --for 2h -- claude       # any tool, capped at two hours
unrestor watch 4821                   # awake while process 4821 runs
unrestor hold --for 90m               # a plain keep-awake with a timer
unrestor status
```

## Why

macOS sleeps when you close the lid unless a charger, an external display, and
a keyboard are attached. `caffeinate` does not reliably stop lid-close sleep,
and `sudo pmset disablesleep 1` does but is global and easy to forget: a crash,
a forgotten `off`, or a reboot can leave a Mac awake in a bag.

Unrestor is a safe wrapper around that switch:

- **Released automatically.** A hold lives and dies with the command, process,
  or timer that asked for it. Quit, crash, or lose the connection and the
  background service releases it and restores your original setting.
- **Works on battery.** Lid-closed holds do not need a charger.
- **Limits that win.** It lets the Mac sleep when the battery drops below a
  floor (default 20%, never below 10%), when the Mac runs hot, or when you chose
  power-only and unplug. The background service enforces these itself.
- **Tool-agnostic.** Anything you can start from a terminal works.
- **Local and minimal.** No account and no telemetry. The only network request
  is an optional once-a-day look at this project's public release page, for
  updates. Turn it off in the menu and the app never goes online.

## Install

Unrestor is not notarized by Apple, because that needs a paid developer account.
It is ad-hoc signed and built in the open by GitHub Actions, so you can read the
code and check the build. macOS therefore asks you to approve it once.
Requires macOS 14 or later.

### Option 1: Homebrew

```sh
brew install --cask GAM3RG33K/tap/unrestor
sudo unrestor install
```

The cask clears the download warning for you and puts `unrestor` on your PATH.

### Option 2: Download the DMG

1. Download `Unrestor-VERSION.dmg` from the
   [latest release](https://github.com/GAM3RG33K/unrestor/releases/latest) and
   drag **Unrestor** to **Applications**.
2. Open it. macOS says it cannot verify the app. Go to **System Settings →
   Privacy & Security**, scroll down, and choose **Open Anyway**. (Or in
   Terminal: `xattr -dr com.apple.quarantine /Applications/Unrestor.app`.)
3. In the menu-bar app, choose **Install Background Service…** and enter your
   password. Or in Terminal:

   ```sh
   sudo /Applications/Unrestor.app/Contents/Helpers/unrestor install
   ```

### Option 3: Build from source

```sh
git clone https://github.com/GAM3RG33K/unrestor && cd unrestor
scripts/make-app.sh              # builds dist/Unrestor.app and a DMG
sudo dist/Unrestor.app/Contents/Helpers/unrestor install
```

### Check it works

```sh
unrestor status          # "Background service: running"
unrestor run -- sleep 30 # close the lid; it keeps going
```

To put the command on your PATH after a DMG install:

```sh
sudo ln -s /Applications/Unrestor.app/Contents/Helpers/unrestor /usr/local/bin/unrestor
```

## Use it

| Command | What it does |
|---|---|
| `unrestor run [--for TIME] -- COMMAND` | Awake until COMMAND exits. Its exit code passes through. |
| `unrestor watch PID [--for TIME]` | Awake while process PID runs. |
| `unrestor hold [--for TIME]` | Awake until Ctrl-C, or until TIME passes. |
| `unrestor status` | Is the service running, and what is holding the Mac awake? |
| `unrestor install` / `uninstall` | Add or remove the background service (needs `sudo`). |
| `unrestor help` | The full guide, including troubleshooting. |

TIME looks like `90m`, `2h`, `1h30m`. Each command stays in the foreground
until it is done; add `&` to background one.

The **menu-bar app** adds a switch and timed buttons, shows what is holding the
Mac awake, and sets the limits (battery floor, power-only, Low Power Mode). The
command-line tool works without the app running.

## Troubleshooting

| Problem | Fix |
|---|---|
| "The background service is not running" | `sudo unrestor install` |
| macOS blocks the app from opening | System Settings → Privacy & Security → **Open Anyway** |
| The Mac still sleeps | `unrestor status` names the reason: low battery, heat, power-only, or no service. |
| Check the system setting by hand | `pmset -g \| grep SleepDisabled` (1 means sleep is blocked) |
| Sleep stays blocked after quitting everything | `sudo unrestor uninstall`. If it still reads 1 and you did not set it, `sudo pmset -a disablesleep 0`. |

## Updates

The menu-bar app checks GitHub once a day for a newer release (turn it off with
**Check for updates automatically**, or press **Check for Updates** any time).
When one exists, **Download & Install** fetches the DMG over HTTPS, checks it
against the SHA-256 published beside it, verifies the new app, swaps it in, and
restarts Unrestor. A manual hold ends when it restarts; commands you started
with `unrestor run` keep running.

The check sends nothing about you or your Mac: no version, no id, no cookies.
It is not a signature check. Releases are not signed by a developer, so the
checksum catches a corrupt download, not a compromised GitHub account.

If the app asks to **Update Background Service**, do that: it makes the root
service match the new app (macOS asks for your password).

With Homebrew, `brew upgrade --cask unrestor` also works.

## Uninstall

```sh
sudo unrestor uninstall     # stops the service and restores your sleep setting
```

Then delete `Unrestor.app`, or run `brew uninstall --cask unrestor`. Your
settings are in `~/Library/Application Support/Unrestor`.

## How it works

`unrestor` connects to a small root background service over a private Unix
socket and renews its hold every second. The service changes one system setting
and records the original so it can restore it after a crash or reboot. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [SECURITY.md](SECURITY.md) for
what it can and cannot do.

## Contributing

```sh
swift build && swift test
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

Unrestor is derived from [Let It Brew](https://github.com/ruban-24/letitbrew)
by Ruban (Apache-2.0). See [NOTICE](NOTICE).

## License

Apache License 2.0. See [LICENSE](LICENSE).
