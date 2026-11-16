# Security policy

## Supported versions

Security and power-safety fixes go into the newest release only.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for this repository. Do not put
exploit details, credentials, or private paths in a public issue. Include the
Unrestor version, macOS version, Mac model, and the smallest safe reproduction.

## What the privileged service can do

Unrestor installs a launchd daemon that runs as root. It exposes exactly three
named, reversible operations over XPC: hold or release `disablesleep`, switch
Low Power Mode on or off for a held session, and report its build. It has no
command runner and no file access for clients.

- It accepts connections only from a client whose Apple code signature has this
  app's bundle identifier and Team ID, checked by the system on every message.
- The app talks only to a daemon whose signature matches the same Team ID and
  the exact build embedded in the app.
- Every hold belongs to one connection. When that connection ends for any
  reason, the daemon releases it.
- Before changing a setting it records the original value on disk. At launch it
  restores any recorded value, so a crash or reboot cannot leave sleep disabled.

The request files that `unrestor` writes live in your own
`~/Library/Application Support/Unrestor/requests`, mode 0700. They can only ask
the app to hold, never to do more, and the app's limits still apply.

## If sleep seems stuck

1. Keep physical access to the Mac and save your work.
2. Quit Unrestor from its menu.
3. Record the value without forcing it:

   ```sh
   pmset -g | grep SleepDisabled
   ```

Forcing it to `0` destroys evidence and assumes your Mac started with sleep
enabled. Report the reading instead.

## What not to publish

Do not publish Apple credentials, signing certificates, private keys, or
notarization credentials in an issue, pull request, log, or conversation.
