# Architecture

| Target | Kind | Responsibility |
|---|---|---|
| `UnrestorCore` | library | Hold policy and safety limits, protocol, socket client, settings, request files. Pure and tested. |
| `UnrestorDaemonCore` | library | Hold coordinator and restore record, per-connection handler, Unix-socket server. |
| `unrestor-daemon` | executable | The root launchd daemon. A thin shell around `UnrestorDaemonCore`. |
| `unrestor` | executable | The CLI, including `install` and `uninstall`. |
| `UnrestorApp` | executable | The menu-bar app. `scripts/make-app.sh` wraps it into `Unrestor.app`. |

`swift build` compiles all of it. There is no Xcode project and no Apple
Developer account in the loop.

## How a hold works

```
unrestor run -- cmd                     menu-bar switch
      |                                       |
      |  connect, then HOLD once a second     |
      v                                       v
   /var/run/unrestor.sock   (owned by you, mode 0600)
      |
      v
   unrestor-daemon (root)
      checks the peer uid, re-checks safety limits on every HOLD
      -> pmset -a disablesleep 1     (and 0 on release)
```

Each client has one connection and one hold. Holds union across clients, and
the last release restores the original setting.

### Protocol

Newline-delimited text. Client commands: `HELLO 1`,
`HOLD floor=20 power-only=0 low-power=0`, `RELEASE`. Replies: `OK unrestor
VERSION`, `HELD`, `RELEASED reason`, `ERR message`. Anything else is refused
with no effect. `HOLD` is a heartbeat: it renews a 10-second lease and re-checks
the limits.

### Safety, in the daemon

`HoldPolicy.safetyRelease` is applied by the daemon to every `HOLD`, using its
own battery and thermal reading, and a clamped copy of the client's settings:

- The battery floor is clamped to at least 10%.
- A hot Mac (`serious` or `critical`) or an unreadable power state always
  releases.
- Power-only is honored when the client asks for it.

A hold ends when the client says `RELEASE`, when its connection closes, or when
its lease runs out. On SIGTERM (`launchctl bootout`, shutdown) the daemon closes
every connection and restores the setting before it exits.

### Restore record

Before the first change, the coordinator writes the prior `SleepDisabled` and
energy-mode values to `/var/db/unrestor` (root-only). The last release restores
them and deletes the record. At launch the daemon restores any leftover record,
so a crash or reboot cannot strand the setting. If a restore fails the record
stays and later requests retry it.

## Install

`sudo unrestor install` (also reachable from the app via the standard password
prompt):

1. Refuses unless run as root; learns the allowed user from `--uid` or
   `SUDO_UID`.
2. Checks `/Library/PrivilegedHelperTools` is root-owned and not group or other
   writable, then copies `unrestor-daemon` there as root-owned, strips the
   download quarantine mark, and re-checks ownership.
3. Writes `/Library/LaunchDaemons/app.unrestor.daemon.plist` (root-owned, 0644)
   pinning the program path and `--allowed-uid`.
4. `launchctl bootstrap system ...`, then waits until the socket answers.

`sudo unrestor uninstall` boots the job out (which restores the setting),
removes the files, and warns if sleep still reads as blocked.

## Updates

`UnrestorCore` holds the pure parts: `AppVersion` (numeric compare, final
releases only), `ReleaseFeed` (parses GitHub's latest-release JSON, requires a
DMG and a `.sha256`, restricts hosts to GitHub over HTTPS), `FileHash`, and
`UpdateScript` (the shell script that swaps the app, arguments passed
positionally so paths cannot inject commands). All of it is unit tested, and
the script is run for real against temp folders, including the failure and
"app never quit" paths.

`InstallSource` tells a Homebrew install (the cask's `Caskroom` folder plus
`brew`) from a direct one, and `BrewUpdateScript` is the fixed script Terminal
runs for a Homebrew install: `brew update`, `brew upgrade --cask`, then
`sudo unrestor install`. Its arguments are passed positionally and it is tested
against fake `brew`, `sudo`, and `unrestor` programs, including the failure path.

`UnrestorApp/Updater` does the I/O: an ephemeral `URLSession` (no cookies or
cache), `hdiutil attach` to read the DMG, `codesign --verify`, and a detached
`/bin/sh` that finishes the swap after the app exits. For a direct install the updater never touches
the root service; the app compares the service's version (from `HELLO`) with its
own and offers to re-run the installer.

## The request files

While a CLI command runs it also writes a small JSON file in
`~/Library/Application Support/Unrestor/requests` so the menu-bar app can list
it. They are display only; the hold is the CLI's own connection. Finished or
dead requests are cleaned up by whoever reads them.

## What `swift test` does and does not cover

Covered, as a normal user: the policy, the protocol, the coordinator and restore
record, the per-connection handler, and the daemon over a real Unix socket
(permissions 0600, hard limits, release on disconnect, release on stop).

Not covered, because they need root, launchd, or a GUI. Check these by hand
before a release:

1. `sudo unrestor install`; `unrestor status` shows the service running.
2. `unrestor run -- sleep 120`, close the lid, reopen: `sleep` finished on time.
3. `kill -9` the CLI mid-hold: `pmset -g | grep SleepDisabled` returns to its
   prior value within about 10 seconds.
4. `sudo kill -9` the daemon during a hold; launchd restarts it and the setting
   is restored at launch.
5. Unplug below the floor: the hold releases and `unrestor status` says why.
6. `sudo unrestor uninstall` leaves no files and the setting restored.
7. The menu-bar app's switch, **Install Background Service…**, and limits.
