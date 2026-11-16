# Homebrew cask for Unrestor. Copy this file to Casks/unrestor.rb in your tap
# repository (github.com/GAM3RG33K/homebrew-tap), then:
#   brew install --cask GAM3RG33K/tap/unrestor
# Update `version` and `sha256` for every release (scripts/build-release.sh
# prints both).
cask "unrestor" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/GAM3RG33K/unrestor/releases/download/v#{version}/Unrestor-#{version}.dmg"
  name "Unrestor"
  desc "Keep your MacBook awake with the lid closed while work runs"
  homepage "https://github.com/GAM3RG33K/unrestor"

  depends_on macos: ">= :sonoma"

  app "Unrestor.app"
  binary "#{appdir}/Unrestor.app/Contents/Helpers/unrestor"

  uninstall quit: "app.unrestor"

  zap trash: [
    "~/Library/Application Support/Unrestor",
    "~/Library/Preferences/app.unrestor.plist",
  ]
end
