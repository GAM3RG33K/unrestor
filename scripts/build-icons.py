#!/usr/bin/env python3
"""Generate every Unrestor icon from one definition. Developer tool: the outputs
(assets/icon/*, site favicons) are committed, so building the app never needs it.

Needs: python3, rsvg-convert (brew install librsvg), iconutil (macOS).
Run:   python3 scripts/build-icons.py
"""
import math, pathlib, shutil, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICONS = ROOT / "assets" / "icon"
SITE = ROOT / "site"

INK, INK2, AMBER, DEEP = "#0a0c13", "#171b28", "#ffb347", "#e8831a"

# ---- The mark, on a 64x64 grid -------------------------------------------
# An open eye whose pupil is a crescent moon: awake all night.
EYE = "M4 32C12 19 22 12 32 12C42 12 52 19 60 32C52 45 42 52 32 52C22 52 12 45 4 32Z"
# Closed eye for the resting state: a lid line and three lashes.
LID = "M6 27C18 41 46 41 58 27"
LASHES = "M17 37L13.5 43.5M32 40.5V48M47 37L50.5 43.5"


def crescent(a, ra, b, rb):
    """A path for circle A minus circle B (a crescent), from real intersections."""
    (ax, ay), (bx, by) = a, b
    d = math.hypot(bx - ax, by - ay)
    x = (d * d + ra * ra - rb * rb) / (2 * d)
    h = math.sqrt(ra * ra - x * x)
    ux, uy = (bx - ax) / d, (by - ay) / d
    mx, my = ax + ux * x, ay + uy * x
    p1 = (mx - uy * h, my + ux * h)
    p2 = (mx + uy * h, my - ux * h)

    def flags(c, r, s, e, mid_dir):
        mid = (c[0] + mid_dir[0] * r, c[1] + mid_dir[1] * r)
        ang = lambda p: math.atan2(p[1] - c[1], p[0] - c[0])
        a_s, a_m, a_e = ang(s), ang(mid), ang(e)
        cw = (a_m - a_s) % (2 * math.pi) < (a_e - a_s) % (2 * math.pi)  # increasing angle
        sweep = 1 if cw else 0
        span = ((a_e - a_s) % (2 * math.pi)) if cw else ((a_s - a_e) % (2 * math.pi))
        return (1 if span > math.pi else 0), sweep

    # Outer edge: the part of A away from B. Inner edge: the part of B inside A.
    la, sa = flags(a, ra, p1, p2, (-ux, -uy))
    lb, sb = flags(b, rb, p2, p1, (ux * -1, uy * -1))
    f = lambda v: f"{v:.2f}".rstrip("0").rstrip(".")
    return (f"M{f(p1[0])} {f(p1[1])}A{ra} {ra} 0 {la} {sa} {f(p2[0])} {f(p2[1])}"
            f"A{rb} {rb} 0 {lb} {sb} {f(p1[0])} {f(p1[1])}Z")


MOON = crescent((31.5, 32.5), 13.5, (38, 28), 10.5)


def svg(view, body, size=None, extra=""):
    w = f' width="{size}" height="{size}"' if size else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}"{w}{extra}>\n{body}\n</svg>\n')


def glyph(awake):
    """Menu-bar template: solid black on transparent. macOS recolors it."""
    if awake:
        body = (f'<path d="{EYE}" fill="none" stroke="#000" stroke-width="5" stroke-linejoin="round"/>\n'
                f'<path d="{MOON}" fill="#000"/>')
    else:
        body = (f'<path d="{LID}" fill="none" stroke="#000" stroke-width="5" stroke-linecap="round"/>\n'
                f'<path d="{LASHES}" fill="none" stroke="#000" stroke-width="5" stroke-linecap="round"/>')
    return svg("0 0 64 64", body, 64)


def mark(on_dark=True):
    """The colored mark for the site and README, transparent background."""
    ink = AMBER
    body = (f'<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{AMBER}"/><stop offset="1" stop-color="{DEEP}"/></linearGradient></defs>\n'
            f'<path d="{EYE}" fill="none" stroke="url(#g)" stroke-width="5" stroke-linejoin="round"/>\n'
            f'<path d="{MOON}" fill="url(#g)"/>')
    return svg("0 0 64 64", body, 64)


def app_icon():
    stars = "".join(
        f'<circle cx="{x}" cy="{y}" r="{r}" fill="#fff" opacity="{o}"/>'
        for x, y, r, o in [(250, 250, 5, .7), (330, 180, 3.5, .5), (720, 205, 4.5, .6),
                           (790, 300, 3, .5), (210, 700, 3.5, .4), (800, 760, 4, .45), (610, 160, 3, .4)])
    body = f'''<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a2036"/><stop offset="1" stop-color="{INK}"/></linearGradient>
  <radialGradient id="glow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="{AMBER}" stop-opacity=".42"/><stop offset="1" stop-color="{AMBER}" stop-opacity="0"/></radialGradient>
  <linearGradient id="amber" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffc66b"/><stop offset="1" stop-color="{DEEP}"/></linearGradient>
  <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000" flood-opacity=".45"/></filter>
  <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="1.5"/></filter>
  <clipPath id="body"><rect x="100" y="100" width="824" height="824" rx="188"/></clipPath>
</defs>
<rect x="100" y="100" width="824" height="824" rx="188" fill="url(#bg)" filter="url(#shadow)"/>
<g clip-path="url(#body)">
  <circle cx="512" cy="520" r="400" fill="url(#glow)"/>
  {stars}
  <rect x="100" y="100" width="824" height="824" fill="none" stroke="#fff" stroke-opacity=".07" stroke-width="3"/>
</g>
<g transform="translate(512 512) scale(11) translate(-32 -32)">
  <path d="{EYE}" fill="{AMBER}" fill-opacity=".07"/>
  <path d="{EYE}" fill="none" stroke="{AMBER}" stroke-width="5" stroke-linejoin="round" opacity=".5" filter="url(#soft)"/>
  <path d="{EYE}" fill="none" stroke="url(#amber)" stroke-width="5" stroke-linejoin="round"/>
  <path d="{MOON}" fill="{AMBER}" opacity=".55" filter="url(#soft)"/>
  <path d="{MOON}" fill="url(#amber)"/>
</g>'''
    return svg("0 0 1024 1024", body, 1024)


def favicon():
    body = f'''<defs><linearGradient id="a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffc66b"/><stop offset="1" stop-color="{DEEP}"/></linearGradient></defs>
<rect width="64" height="64" rx="14" fill="{INK}"/>
<path d="{EYE}" fill="none" stroke="url(#a)" stroke-width="5.5" stroke-linejoin="round" transform="translate(32 32) scale(.86) translate(-32 -32)"/>
<path d="{MOON}" fill="url(#a)" transform="translate(32 32) scale(.86) translate(-32 -32)"/>'''
    return svg("0 0 64 64", body, 64)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def raster(src, dst, px):
    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), str(src), "-o", str(dst)], check=True)


def main():
    if not shutil.which("rsvg-convert"):
        sys.exit("rsvg-convert not found: brew install librsvg")

    write(ICONS / "unrestor-icon.svg", app_icon())
    write(ICONS / "unrestor-glyph.svg", glyph(True))
    write(ICONS / "unrestor-glyph-resting.svg", glyph(False))
    write(ICONS / "unrestor-mark.svg", mark())
    write(ICONS / "unrestor-favicon.svg", favicon())

    # macOS app icon (.icns) from the 1024 master.
    with tempfile.TemporaryDirectory() as tmp:
        iconset = pathlib.Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for base in (16, 32, 128, 256, 512):
            raster(ICONS / "unrestor-icon.svg", iconset / f"icon_{base}x{base}.png", base)
            raster(ICONS / "unrestor-icon.svg", iconset / f"icon_{base}x{base}@2x.png", base * 2)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICONS / "AppIcon.icns")], check=True)

    raster(ICONS / "unrestor-icon.svg", ICONS / "unrestor-icon-512.png", 512)
    # Site: SVG favicon plus PNG fallbacks.
    shutil.copy(ICONS / "unrestor-favicon.svg", SITE / "favicon.svg")
    shutil.copy(ICONS / "unrestor-mark.svg", SITE / "mark.svg")
    raster(ICONS / "unrestor-favicon.svg", SITE / "favicon-32.png", 32)
    raster(ICONS / "unrestor-favicon.svg", SITE / "apple-touch-icon.png", 180)
    raster(ICONS / "unrestor-icon.svg", SITE / "icon-512.png", 512)
    print("Icons written to", ICONS, "and", SITE)


if __name__ == "__main__":
    main()
