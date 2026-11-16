# Security policy

## Supported versions

Security and power-safety fixes go into the newest release only.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for this repository. Do not put
exploit details, credentials, or private paths in a public issue. Include the
Unrestor version, macOS version, Mac model, and the smallest safe reproduction.

## What the background service is

`sudo unrestor install` sets up a launchd daemon that runs as root. This
section says exactly what that means, so you can decide whether to trust it.

**What it can do.** It accepts a few text commands on a Unix socket: `HELLO`,
`HOLD`, `RELEASE`. A hold runs `pmset -a disablesleep 1`; a release restores it.
It can also switch Low Power Mode on and off while a hold is active. The
`pmset` arguments are fixed. It cannot run your commands, read files for a
client, or do anything else.

**Who can talk to it.** Only the user who ran the installer. The socket
(`/var/run/unrestor.sock`) is owned by that user with mode 0600, and the daemon
re-checks the peer's user id on every connection. The allowed user id is fixed
in a root-owned launchd job, so it cannot be changed without root.

**What stops a client abusing it.** The daemon, not the client, enforces the
safety limits on every heartbeat:

- It never honors a battery floor below 10%, whatever the client asks.
- It always releases when the Mac is hot or its power state cannot be read.
- It releases a hold that is not renewed within 10 seconds, so a hung or killed
  client cannot strand one.
- It releases when the connection closes for any reason.
- Before changing the setting it records the original value in
  `/var/db/unrestor` (root-only) and restores it at the next launch, so a crash
  or reboot cannot leave sleep disabled.

**What a malicious program running as you could do.** Hold the Mac awake, up to
those limits. That is the whole of it. It would not gain root.

**Where the program runs from.** The installer copies the daemon to
`/Library/PrivilegedHelperTools/app.unrestor.daemon`, owned by root and not
writable by anyone else, and refuses to install if that folder is not
root-only writable. A root service must never run a file you can edit.

**What is not protected.** The app is ad-hoc signed, not notarized, so macOS
cannot vouch for who built it. Builds are made by GitHub Actions from this
source; build it yourself with `scripts/make-app.sh` if you prefer. Anyone with
administrator rights on the Mac can of course change anything.

## If sleep seems stuck

1. Keep physical access to the Mac and save your work.
2. Run `unrestor status`.
3. Run `sudo unrestor uninstall`. It stops the service and restores the setting.
4. Check without forcing it:

   ```sh
   pmset -g | grep SleepDisabled
   ```

If it still reads 1 and you did not set it yourself, report that reading, then
run `sudo pmset -a disablesleep 0`.

## What not to publish

Do not publish credentials, private keys, or tokens in an issue, pull request,
log, or conversation.
