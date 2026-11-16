# Unrestor

**Close the lid. Your work keeps running.**

A minimal macOS menu-bar app and command-line tool that keeps your MacBook
awake, lid closed, while a command, a process, or a timer is running. When the
work stops, the Mac sleeps again. A battery floor and a heat limit always win.

```sh
unrestor run -- npm run build         # awake only while the build runs
unrestor run --for 2h -- claude       # any tool; capped at two hours
unrestor watch 4821                   # awake while process 4821 runs
unrestor on --for 90m                 # manual hold, then sleep
unrestor status
```

## Why

macOS sleeps when you close the lid unless a charger, an external display, and
a keyboard are attached. `caffeinate` does not reliably stop lid-close sleep, and
`sudo pmset disablesleep 1` does but is global and easy to forget: a crash, a
forgotten `off`, or a reboot can leave a Mac awake in a bag.

Unrestor is a safe wrapper around that switch:

- **Released automatically.** A hold lives and dies with the process, timer, or
  toggle that asked for it. Quit the app, crash, or lose the daemon connection
  and the daemon restores your original sleep setting.
- **Works on battery.** Lid-closed holds do not need a charger.
- **Limits that win.** It lets the Mac sleep below a battery floor you choose,
  when the Mac runs hot, or when you chose power-only and unplugged.
- **Tool-agnostic.** Anything you can start from a terminal works.
- **Local and minimal.** No account, no network, no telemetry. Menu-bar only.

## Install

Download the latest DMG from the
[releases page](https://github.com/GAM3RG33K/unrestor/releases/latest), drag
**Unrestor** to `/Applications`, open it, and choose **Set Up Background
Service…**. macOS asks you to allow it once in **System Settings → General →
Login Items**.

Or with Homebrew:

```sh
brew install --cask GAM3RG33K/tap/unrestor
```

Both put the `unrestor` command on your PATH (Homebrew) or at
`/Applications/Unrestor.app/Contents/Helpers/unrestor` (DMG).

The app must be running for holds to take effect. Turn on **Launch at login**
in its menu.

Requires macOS 14 or later.

## How it works

`unrestor run`, `watch`, and `on` write a small request file. The menu-bar app
reads those files once a second, applies the safety limits, and asks a
privileged background service to hold or release sleep. The service is
reversible by design and records the original setting so it can restore it
after a crash or reboot. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Safety

Unrestor changes a system-wide power setting through a privileged service.
Read [SECURITY.md](SECURITY.md) for what it can do, how it proves its identity,
and what to do if you think the setting is stuck.

If you ever need to check by hand: `pmset -g | grep SleepDisabled`.

## Build from source

```sh
swift build
swift test
```

Running the real app needs an Apple-signed build. See
[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Credits

Unrestor is derived from [Let It Brew](https://github.com/ruban-24/letitbrew)
by Ruban (Apache-2.0). See [NOTICE](NOTICE).

## License

Apache License 2.0. See [LICENSE](LICENSE).
