# Homebrew cask for Unrestor. This is the source of truth: the Release workflow
# copies it to Casks/unrestor.rb in github.com/GAM3RG33K/homebrew-tap and sets
# `version` and `sha256` for each release. Edit everything else here.
#   brew install --cask GAM3RG33K/tap/unrestor
cask "unrestor" do
  version "0.1.0"
  sha256 "a1f027b03d4c0dc52b9d6d0555c6f7a1fc398d62c71d03198e1e08fa95ac57e0"

  url "https://github.com/GAM3RG33K/unrestor/releases/download/v#{version}/Unrestor-#{version}.dmg"
  name "Unrestor"
  desc "Keep your MacBook awake with the lid closed while work runs"
  homepage "https://github.com/GAM3RG33K/unrestor"

  depends_on macos: ">= :sonoma"

  app "Unrestor.app"
  binary "#{appdir}/Unrestor.app/Contents/Helpers/unrestor"

  # The app is ad-hoc signed, not notarized (no paid Apple account). Clearing
  # the download quarantine mark lets it open without the Gatekeeper warning.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Unrestor.app"]
  end

  # Removes the root background service before the app goes away.
  uninstall_preflight do
    system_command "#{appdir}/Unrestor.app/Contents/Helpers/unrestor",
                   args:         ["uninstall"],
                   sudo:         true,
                   must_succeed: false
  end

  uninstall quit: "app.unrestor"

  zap trash: [
    "~/Library/Application Support/Unrestor",
    "~/Library/Preferences/app.unrestor.plist",
  ]

  caveats <<~EOS
    One more step: install the background service (asks for your password once):
      sudo unrestor install
    Then try:
      unrestor run -- sleep 30
  EOS
end
