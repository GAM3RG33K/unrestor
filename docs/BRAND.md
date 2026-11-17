# Brand

A short guide to how Unrestor looks and sounds. It exists so the app, the site,
the README, and any fork that wants to stay recognizably "not this project" stay
consistent. Forks must use their own name and icon (see
[CONTRIBUTING.md](../CONTRIBUTING.md)).

## The idea

Unrestor is for work that should not stop. The mark is an **open eye with a
crescent moon for a pupil**: it is awake while the world sleeps. The site pairs
a bright, calm page with a **night window** (the dark product card) to say the
same thing: the lid is closed, the work goes on.

## Name

**Unrestor**, one word, capital U. The command is `unrestor` in lowercase.
Never "UnRestor" or "UNRESTOR".

## Voice

Plain, calm, and specific. Short sentences. Say what it does and what it does
not do. No hype, no fear, no jargon where a normal word works.

- Say "keeps your Mac awake with the lid closed", not "advanced power management".
- Say what a limit does ("sleeps again below 20% battery"), not that it is "smart".
- Be honest about trade-offs (not notarized, root service) in the same breath
  as the benefit.
- The project is personal: first person is fine ("I built it for myself").

Taglines, in order of preference:

1. Close the lid. Your work keeps running.
2. Keep your MacBook awake with the lid closed.
3. A free, open-source keep-awake tool for macOS.

## Color

| Token | Hex | Use |
|---|---|---|
| Night | `#0a0c13` | Dark cards, the icon background, terminal surfaces |
| Night 2 | `#121624` | Raised dark surfaces |
| Paper | `#f4f1ea` | Page background |
| Ink | `#0d0f17` | Text, primary buttons |
| Soft | `#aaa79e` | Second line of a heading, quiet text |
| Muted | `#6c6f7c` | Body copy on light backgrounds |
| Amber | `#ffb347` | Brand accent, awake state, highlights |
| Amber deep | `#e8831a` | Switches, links, the lower end of gradients |
| Dusk | `#8fb0ff` | Secondary accent in code and glows |
| Green | `#2fa866` | Success and "running" |

Amber means awake. Use it for the active state, never for decoration alone.

## Type

**Plus Jakarta Sans** for everything on the site (SIL OFL, served from the site
itself, no font host). Headings: weight 600, tight tracking (-0.04em), with the
second half of a heading in Soft. Code and commands use the system monospace
(SF Mono, Menlo).

## Mark and icon

Source of truth: `scripts/build-icons.py`. Files live in `assets/icon`.

- **App icon:** the amber eye on a night tile (`unrestor-icon.svg`).
- **Mark:** the amber gradient eye on its own (`unrestor-mark.svg`), used in the
  site nav and footer.
- **Menu-bar glyph:** a template image, so macOS tints it. The awake glyph is
  the eye; the resting glyph is a closed eye with lashes.

Leave clear space equal to the pupil's width around the mark. Do not recolor
it, outline it, or place it on a busy background.

## Motion

Motion explains state; it never just decorates. The site uses it for:

- the hero scene, which acts out one real use (type a command, flip the switch,
  close the lid, the build ends, the hold releases),
- reveals on scroll, and a copy button that confirms,
- slow ambient motion (a sheen on the install bar, a drifting command strip).

Everything respects `prefers-reduced-motion`. Nothing on the page makes a
network request.

## Social image

`assets/brand/og-image.svg` is the source of `site/og-image.png` (1200 x 630).
Regenerate it with:

```sh
rsvg-convert -w 1200 -h 630 assets/brand/og-image.svg -o site/og-image.png
```
