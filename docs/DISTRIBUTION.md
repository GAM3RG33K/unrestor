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
   git tag v0.1.6 && git push origin main v0.1.6
   ```

3. The **Release** workflow checks the tag matches the source, runs the tests,
   builds the DMG on GitHub's Mac runner, and publishes the release with the
   DMG and its SHA-256. No Apple certificates are involved.
4. A second job then updates the Homebrew cask in the tap from that published
   release (see below). It needs the `TAP_TOKEN` secret and skips with a
   warning if it is missing.

## Channels

| Channel | Who it serves | Effort |
|---|---|---|
| **GitHub release DMG** | Everyone | Automatic on every tag. |
| **Your Homebrew tap** | People who use `brew` | Low. Create the repo `GAM3RG33K/homebrew-tap`, and add the `TAP_TOKEN` secret (fine-grained token, Contents read/write on that repo only). The Release workflow then copies `packaging/unrestor.rb` to `Casks/unrestor.rb` and sets `version` and `sha256` on every tag. To publish an existing release, run the Release workflow manually with its tag. Install with `brew install --cask GAM3RG33K/tap/unrestor`. |
| **Official homebrew-cask** | Wider reach | Not realistic yet: it asks for notarized apps and a notable project. |
| **Mac App Store** | Not possible | The sandbox forbids a root daemon that changes `pmset`, and it needs a paid account. |

A plain Homebrew *formula* would build from source but cannot install the root
service for you, so the cask is the right shape.

## Updates

The menu-bar app updates itself from your GitHub releases:

1. Once a day (and on **Check for Updates**) it reads
   `api.github.com/repos/GAM3RG33K/unrestor/releases/latest`. It ignores drafts
   and pre-releases, and anything whose tag is not a plain `X.Y.Z`.
2. A release is installable only if it has both `Unrestor-X.Y.Z.dmg` and
   `Unrestor-X.Y.Z.dmg.sha256`, hosted on github.com or githubusercontent.com
   over HTTPS. The release workflow produces both, so a normal tag just works.
3. **Download & Install** downloads the DMG, checks its SHA-256, mounts it,
   copies the app out, confirms it is `app.unrestor` at the expected version
   with the CLI and daemon inside, and runs `codesign --verify --deep --strict`.
4. A small script (`UpdateScript`) waits for the running app to quit, moves the
   old app aside, copies the new one in, and relaunches it. If the copy fails
   the old app is put back.
5. The new app notices when the root service is older than itself and offers
   **Update Background Service**, which re-runs the installer.

It cannot authenticate who built a release: there is no developer signature to
check. The checksum guards against corruption, not a hijacked GitHub account.

If the app is not in a folder the user can write to, the updater opens the
release page instead.

**Homebrew installs update through Homebrew.** The app detects a Homebrew
install (the cask's folder in Homebrew's `Caskroom` plus `brew` beside it).
There, **Download & Install** doesn't swap the app itself, which would leave
Homebrew's record out of date. It opens Terminal and runs:

```sh
brew update && brew upgrade --cask GAM3RG33K/tap/unrestor && sudo unrestor install
```

The last step is needed because `brew upgrade` removes the root service when it
removes the old version. Direct installs never lose the service on update.

To test the whole path, build a copy with an older version and run
`Unrestor.app/Contents/MacOS/Unrestor --update-now` (or
`open -n Unrestor.app --args --update-now`): it checks, installs, and relaunches.

## The website

`site/` is a static page (no build step, no third-party requests) published to
GitHub Pages by the **Pages** workflow on every change under `site/`.

- **Domain.** The site is served from `https://unrestor.harshjoshi.dev`. That is
  the default in the Pages workflow, and it is set as the custom domain in
  Settings → Pages (with a `CNAME` DNS record pointing at `gam3rg33k.github.io`).
  The workflow replaces `__SITE_URL__` in the canonical link, Open Graph and
  Twitter tags, structured data, `sitemap.xml`, `robots.txt`, `llms.txt`, and
  `llms-full.txt`. To use another address, set the repository variable
  `SITE_URL`.
- **Social image.** `site/og-image.png` is generated from
  `assets/brand/og-image.svg` (see [BRAND.md](BRAND.md)).
- **For search and AI tools.** The page has structured data (software
  application and FAQ), a sitemap, and `llms.txt` / `llms-full.txt`.
- **Preview locally.** Copy `site/` somewhere, replace `__SITE_URL__` with
  `http://localhost:8000`, and run `python3 -m http.server 8000` in it.
