# Distribution and signing

## Why Apple signing is required

The daemon is installed with `SMAppService`, which only registers a daemon from
an Apple-signed app in `/Applications`. The app and daemon also verify each
other by Team ID. An unsigned or ad-hoc build cannot run the real service. You
need a paid Apple Developer Program membership and a **Developer ID
Application** certificate.

## One-time setup

1. Pick your bundle identifiers. The defaults in `project.yml` are `app.unrestor`
   (app), `app.unrestor.daemon`, and `app.unrestor.cli`, with `.dev` variants for
   debug builds. Use a reverse-DNS prefix you control, then search and replace
   `app.unrestor` across `project.yml`, `Config/`, `Sources/`, `Tests/`,
   `packaging/`.
2. Replace `TEAMID0000` with your Team ID in `project.yml` and in
   `Sources/UnrestorDaemonCore/BackgroundServiceEligibility.swift` (and the
   matching test fixtures).
3. Install the tools: `brew install xcodegen`.
4. Store notarization credentials once:
   `xcrun notarytool store-credentials unrestor-notary`.

Keep debug and release identifiers separate. A development copy must never share
the production daemon label.

## Development build

```sh
xcodegen generate
xcodebuild -project Unrestor.xcodeproj -scheme Unrestor -configuration Debug \
  -derivedDataPath /private/tmp/unrestor-derived -allowProvisioningUpdates build
```

Copy the built app to `/Applications` to register the service.

## Cutting a release

```sh
git tag v0.1.0 && git push --tags      # creates a draft GitHub release
export UNRESTOR_TEAM_ID=YOURTEAMID
export UNRESTOR_NOTARY_PROFILE=unrestor-notary
scripts/build-release.sh               # signs, notarizes, staples, prints SHA-256
```

Attach `dist/Unrestor-0.1.0.dmg` to the draft release and publish it. The script
publishes nothing itself.

## Channels

| Channel | Who it serves | Effort |
|---|---|---|
| **GitHub release DMG** | Everyone | Required. This is the source of truth. |
| **Your Homebrew tap** | People who use `brew` | Low. Create `homebrew-tap`, copy `packaging/unrestor.rb` to `Casks/unrestor.rb`, bump `version` and `sha256` per release. Install with `brew install --cask GAM3RG33K/tap/unrestor`. |
| **Official homebrew-cask** | Wider reach | Needs a notable project (stars and age) and review. Apply once the tap is stable. |
| **Mac App Store** | Not possible | The sandbox forbids a root daemon that changes `pmset`. |

A plain Homebrew *formula* cannot install the daemon, so distribute the app as a
cask. The cask installs the app and links the `unrestor` command.

## Updates

v0.1 has no built-in updater. Homebrew users run `brew upgrade --cask unrestor`.
DMG users download the new release. After an upgrade the app notices a daemon
from an older build and re-registers it.
