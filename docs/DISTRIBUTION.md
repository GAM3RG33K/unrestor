# Distribution

Unrestor is built to ship without a paid Apple Developer account.

## What users get, and the catch

The app is **ad-hoc signed**, not Developer ID signed or notarized. That means:

- macOS shows a "cannot verify" warning the first time. Users approve it in
  **System Settings → Privacy & Security → Open Anyway**, or you give them the
  Homebrew cask, which clears the quarantine mark for them.
- Nothing about the daemon depends on an Apple Team ID. The root service is
  installed by `sudo unrestor install` from a root-owned location, and trusts
  only the one user who installed it. See [SECURITY.md](../SECURITY.md).

If you later join the Apple Developer Program you can add Developer ID signing
and notarization to `scripts/make-app.sh` without changing the architecture.

## Build

```sh
scripts/make-app.sh
```

It builds a universal (Apple silicon and Intel) release, assembles
`dist/Unrestor.app` with the CLI and daemon in `Contents/Helpers`, ad-hoc signs
it, and writes `dist/Unrestor-VERSION.dmg` and a `.sha256`.

## Cut a release

1. Set the version in `Sources/UnrestorCore/Protocol.swift`
   (`UnrestorVersion.current`) and add notes to `RELEASE-NOTES.md`. Commit.
2. Tag and push:

   ```sh
   git tag v0.1.0 && git push --tags
   ```

3. The **Release** workflow checks the tag matches the source, runs the tests,
   builds the DMG on GitHub's Mac runner, and publishes the release with the
   DMG and its SHA-256. No certificates or secrets are involved.
4. Update the Homebrew cask (below) with the new version and SHA-256.

## Channels

| Channel | Who it serves | Effort |
|---|---|---|
| **GitHub release DMG** | Everyone | Automatic on every tag. |
| **Your Homebrew tap** | People who use `brew` | Low. Create the repo `GAM3RG33K/homebrew-tap`, copy `packaging/unrestor.rb` to `Casks/unrestor.rb`, and bump `version` and `sha256` per release. Install with `brew install --cask GAM3RG33K/tap/unrestor`. |
| **Official homebrew-cask** | Wider reach | Not realistic yet: it asks for notarized apps and a notable project. |
| **Mac App Store** | Not possible | The sandbox forbids a root daemon that changes `pmset`, and it needs a paid account. |

A plain Homebrew *formula* would build from source but cannot install the root
service for you, so the cask is the right shape.

## Updates

v0.1 has no built-in updater. Homebrew users run `brew upgrade --cask unrestor`
then `sudo unrestor install` to refresh the service. DMG users replace the app
and run `sudo unrestor install` again; it is safe to repeat.
