let helpText = """
unrestor \(versionString): keep your Mac awake, lid closed, while work runs.

QUICK START
  1. Install the background service (once, asks for your password):
         sudo unrestor install
  2. Run any command and keep the Mac awake while it runs:
         unrestor run -- npm run build
  3. Close the lid. When the command ends, the Mac can sleep again.

COMMANDS
  unrestor run [--for TIME] [--name NAME] -- COMMAND [ARGS...]
      Run COMMAND and stay awake until it exits. Its exit code is passed on.
  unrestor watch PID [--for TIME] [--name NAME]
      Stay awake while the process PID is running.
  unrestor hold [--for TIME]
      Stay awake until you press Ctrl-C (or TIME passes).
  unrestor status
      Show whether the service is running and what is holding the Mac awake.
  unrestor install      Install the background service. Needs sudo.
  unrestor uninstall    Remove it and restore your sleep setting. Needs sudo.
  unrestor help         Show this text.   unrestor --version

TIME looks like 90m, 2h, 1h30m, 45s. A bare number means minutes.

Each of these keeps working until you stop it. They stay in the foreground; add
& to put one in the background, or use the Unrestor menu-bar app's switch.

WHEN THE MAC SLEEPS ANYWAY
  Unrestor lets go on purpose when the battery is low (default below 20%, and
  never below 10%), when the Mac runs hot, or when you chose power-only and
  unplug. The menu-bar app sets these limits; this tool reads the same ones.

TROUBLESHOOTING
  "The background service is not running"
      Run: sudo unrestor install
  Installed, but the Mac still sleeps
      Run: unrestor status       It names the reason: battery, heat, or no service.
  Check the system setting by hand
      pmset -g | grep SleepDisabled      (1 means sleep is blocked)
  Sleep stays blocked after quitting everything (should not happen)
      Run: sudo unrestor uninstall   It restores the setting. If it still says 1
      and you did not set it yourself, run: sudo pmset -a disablesleep 0

UNINSTALL
  sudo unrestor uninstall, then delete Unrestor.app. Your settings live in
  ~/Library/Application Support/Unrestor and can be deleted too.

More: https://github.com/GAM3RG33K/unrestor
"""
