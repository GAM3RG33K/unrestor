# Architecture

Unrestor has three parts and one shared folder of request files.

| Target | Kind | Responsibility |
|---|---|---|
| `UnrestorCore` | SwiftPM library | Request files, hold policy, duration parsing, `pmset` and power readers. Pure and tested. |
| `UnrestorDaemonCore` | SwiftPM library | XPC protocol, hold coordinator, restore record, signing checks. |
| `UnrestorDaemon` | executable | The root launchd daemon. Thin shell around the coordinator. |
| `UnrestorApp` | executable | Menu-bar app: polls requests, applies policy, talks to the daemon. |
| `unrestor` | executable | The CLI. Writes and removes request files; reads status. |

`swift build` compiles all five. Release builds come from Xcode via
`project.yml`, which embeds the daemon and CLI inside the app bundle.

## Flow

```
unrestor run / watch / on          menu-bar switch
        \                              /
         v                            v
   ~/Library/Application Support/Unrestor/requests/*.json
                      |  app polls once a second
                      v
   HoldPolicy.decide(requests, settings, power)  -> hold or release
                      |  XPC, one authenticated connection
                      v
   UnrestorDaemon (root)  ->  pmset -a disablesleep 1 / 0
```

## Requests

A request is one JSON file: an id, a label, an optional pid, and an optional
expiry. It is active until the file is removed, it expires, or its pid exits.
The app deletes finished requests, so a crashed `unrestor run` leaves nothing
behind. `unrestor on` and the menu switch share the single id `manual`.

## Policy

`HoldPolicy.decide` is pure. With at least one active request it holds unless:
the power reading is untrusted, the Mac is `serious` or `critical` thermally,
power-only is on and the Mac is on battery, or the battery is below the floor.
Safety limits always beat a request.

## Daemon

The daemon exposes `setLidClosedHold`, `setLowPowerModeHold`, and a handshake.
Holds are per connection and union across connections. Before the first change
it writes a debt record of the prior `SleepDisabled` and energy-mode values; the
last release restores them and deletes the record. At launch it restores any
leftover record, so a crash or reboot cannot strand the setting. If a restore
fails the record stays and every later request retries it.

The app refuses to talk to a daemon that is not signed by the same Team ID and
the exact build embedded in the app. The daemon accepts only the matching app.

## What is not covered by `swift test`

`UnrestorApp` and `UnrestorDaemon` are not unit tested: they need a signed bundle
and a real launchd registration. Verify them by hand before a release:

1. Install a signed build in `/Applications`; set up the service.
2. `unrestor run -- sleep 60`, close the lid, confirm it keeps running.
3. Quit the app mid-hold; confirm `pmset -g | grep SleepDisabled` returns to its
   prior value.
4. `kill -9` the daemon during a hold; confirm it restores at relaunch.
5. Unplug below the battery floor; confirm the hold releases.
