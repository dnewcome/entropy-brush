#!/usr/bin/env python3
"""Generate the entropybrush hero/social image as an SVG.

A spinning tilted disc (canvas) with spiral paint arms, a brush contacting it,
and paint flinging off the rim in trailed droplets. Dark, on-brand.
"""
import math, random

random.seed(7)

W, H = 1200, 630
CX, CY = 470, 330          # disc centre (screen)
RX, RY = 268, 150          # disc radii (tilted ellipse)
COLORS = ["#3A86FF", "#E23B6D", "#F4B41E", "#2EC4B6", "#E4472E", "#8B5CF6"]

out = []
def add(s): out.append(s)

# ---- helpers -------------------------------------------------------------
def disc_pt(ang, r):
    """Point on the tilted disc at polar (ang, r in 0..1)."""
    return (CX + RX * r * math.cos(ang), CY + RY * r * math.sin(ang))

def arm_pt(base, t, twist):
    """A spiral arm point: t in 0..1 from centre to rim."""
    r = 0.16 + 0.84 * t
    a = base + twist * t
    return disc_pt(a, r)

# ---- header / defs -------------------------------------------------------
add(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">')
add('<defs>')
add('<radialGradient id="bg" cx="42%" cy="46%" r="75%">'
    '<stop offset="0" stop-color="#26262d"/><stop offset="0.55" stop-color="#191a1e"/>'
    '<stop offset="1" stop-color="#101012"/></radialGradient>')
add('<radialGradient id="glow" cx="50%" cy="50%" r="50%">'
    '<stop offset="0" stop-color="#3a86ff" stop-opacity="0.28"/>'
    '<stop offset="0.6" stop-color="#3a86ff" stop-opacity="0.05"/>'
    '<stop offset="1" stop-color="#3a86ff" stop-opacity="0"/></radialGradient>')
add('<radialGradient id="disc" cx="44%" cy="38%" r="74%">'
    '<stop offset="0" stop-color="#3b3d47"/><stop offset="1" stop-color="#26272e"/></radialGradient>')
add('<linearGradient id="handle" x1="0" y1="0" x2="1" y2="1">'
    '<stop offset="0" stop-color="#d98a3a"/><stop offset="1" stop-color="#9c5a1f"/></linearGradient>')
add('<linearGradient id="ferrule" x1="0" y1="0" x2="1" y2="1">'
    '<stop offset="0" stop-color="#e9edf2"/><stop offset="0.5" stop-color="#aeb4bd"/>'
    '<stop offset="1" stop-color="#7c828c"/></linearGradient>')
add('<filter id="mblur" x="-30%" y="-30%" width="160%" height="160%">'
    '<feGaussianBlur stdDeviation="2.2"/></filter>')
add('<filter id="soft" x="-40%" y="-40%" width="180%" height="180%">'
    '<feGaussianBlur stdDeviation="1.1"/></filter>')
add('<filter id="ds" x="-40%" y="-40%" width="180%" height="180%">'
    '<feDropShadow dx="0" dy="8" stdDeviation="10" flood-color="#000" flood-opacity="0.55"/></filter>')
add('</defs>')

# ---- background ----------------------------------------------------------
add(f'<rect width="{W}" height="{H}" fill="url(#bg)"/>')
add(f'<ellipse cx="{CX}" cy="{CY}" rx="{RX*1.9:.0f}" ry="{RY*1.9:.0f}" fill="url(#glow)"/>')

# ---- motion arcs (behind disc) ------------------------------------------
for i, rr in enumerate((1.14, 1.24, 1.35)):
    a0, a1 = math.radians(200 + i*8), math.radians(200 + i*8 + 150)
    n = 40
    pts = []
    for k in range(n+1):
        a = a0 + (a1-a0)*k/n
        pts.append(f"{CX + RX*rr*math.cos(a):.1f},{CY + RY*rr*math.sin(a):.1f}")
    add(f'<polyline points="{" ".join(pts)}" fill="none" stroke="#8fb6ff" '
        f'stroke-opacity="{0.16 - i*0.04:.2f}" stroke-width="{2.5 - i*0.5:.1f}" '
        f'stroke-linecap="round" filter="url(#soft)"/>')

# ---- the disc (spinning canvas) -----------------------------------------
add('<g filter="url(#ds)">')
# thickness / side of the spinning disc (a coin edge for 3D)
add(f'<ellipse cx="{CX}" cy="{CY+18}" rx="{RX}" ry="{RY}" fill="#0e0f12"/>')
add(f'<ellipse cx="{CX}" cy="{CY+9}" rx="{RX}" ry="{RY}" fill="#242530"/>')
# top canvas surface
add(f'<ellipse cx="{CX}" cy="{CY}" rx="{RX}" ry="{RY}" fill="url(#disc)" '
    f'stroke="#4f5160" stroke-width="2"/>')
add('</g>')
# luminous rim highlight (spin sheen)
add(f'<ellipse cx="{CX}" cy="{CY}" rx="{RX-2}" ry="{RY-2}" fill="none" '
    f'stroke="#7fb0ff" stroke-opacity="0.45" stroke-width="2.5" filter="url(#soft)"/>')

# ---- spiral paint arms on the disc --------------------------------------
NARMS = 6
TWIST = 1.15
arms = []
add('<g filter="url(#mblur)">')
for k in range(NARMS):
    base = 2*math.pi*k/NARMS + 0.15
    col = COLORS[k % len(COLORS)]
    n = 26
    pts = [arm_pt(base, k2/n, TWIST) for k2 in range(n+1)]
    d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts)
    # taper: thicker toward rim
    add(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="13" '
        f'stroke-linecap="round" stroke-opacity="0.92"/>')
    arms.append((base, col, pts))
# bright center hub
add(f'<ellipse cx="{CX}" cy="{CY}" rx="16" ry="10" fill="#f4f1ea" opacity="0.85"/>')
add('</g>')

# ---- paint flinging off the rim -----------------------------------------
def norm(vx, vy):
    m = math.hypot(vx, vy) or 1.0
    return vx/m, vy/m

add('<g>')
for base, col, pts in arms:
    P = pts[-1]                      # rim end of the arm
    Pm = pts[-3]
    tx, ty = norm(P[0]-Pm[0], P[1]-Pm[1])          # tangent (spin direction)
    ox, oy = norm(P[0]-CX, P[1]-CY)                # outward
    vx, vy = norm(0.65*tx + 0.85*ox, 0.65*ty + 0.85*oy)
    speed = random.uniform(150, 240)
    grav = random.uniform(320, 460)
    npd = random.randint(5, 8)
    trail = []
    for j in range(npd):
        s = (j+1)/npd
        x = P[0] + vx*speed*s
        y = P[1] + vy*speed*s + 0.5*grav*s*s
        rad = max(1.6, 9*(1-s) + 2)
        trail.append((x, y, rad))
    # connecting streak
    streak = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y, _ in [(P[0],P[1],0)]+trail)
    add(f'<path d="{streak}" fill="none" stroke="{col}" stroke-opacity="0.5" '
        f'stroke-width="3.5" stroke-linecap="round" filter="url(#soft)"/>')
    for x, y, rad in trail:
        add(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{rad:.1f}" fill="{col}" filter="url(#soft)"/>')
    # a couple of satellite specks
    for _ in range(random.randint(1, 3)):
        sx = P[0] + vx*random.uniform(40, speed) + random.uniform(-18, 18)
        sy = P[1] + vy*random.uniform(20, speed) + random.uniform(-14, 22)
        add(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{random.uniform(1.4,3.4):.1f}" '
            f'fill="{col}" opacity="0.9"/>')
add('</g>')

# ---- brush (contacting the disc) ----------------------------------------
# Contact near the top of the disc; the brush rises up-right out of the canvas.
contact = disc_pt(math.radians(-74), 0.5)
ang = 24  # degrees the handle tilts to the right of vertical
add(f'<g transform="translate({contact[0]:.1f} {contact[1]:.1f}) rotate({ang})">')
# bristles: tip at the surface (0,2) fanning up to the ferrule (y=-58)
add('<path d="M0 4 C -7 -18, -10 -40, -16 -58 L 16 -58 C 10 -40, 7 -18, 0 4 Z" fill="#2c2d35"/>')
add(f'<path d="M-2 2 C -6 -16, -8 -36, -12 -54 L 7 -56 C 5 -36, 3 -16, -2 2 Z" '
    f'fill="{COLORS[0]}" opacity="0.6"/>')
# ferrule (metal band)
add('<rect x="-16" y="-86" width="32" height="30" rx="3" fill="url(#ferrule)"/>')
add('<rect x="-16" y="-74" width="32" height="2.5" fill="#000" opacity="0.22"/>')
# handle (tapered, rounded end)
add('<path d="M-15 -86 L 15 -86 L 9 -252 Q 0 -264 -9 -252 Z" fill="url(#handle)"/>')
add('<path d="M-15 -86 L -7 -86 L -5 -250 Q -8 -256 -9 -250 Z" fill="#fff" opacity="0.18"/>')
add('</g>')
# a paint blob where the brush meets the canvas
add(f'<circle cx="{contact[0]:.1f}" cy="{contact[1]:.1f}" r="8" fill="{COLORS[0]}"/>')
add(f'<circle cx="{contact[0]:.1f}" cy="{contact[1]:.1f}" r="8" fill="#fff" opacity="0.15"/>')

# ---- wordmark ------------------------------------------------------------
add('<g transform="translate(64 548)">')
# tiny paint-drop glyph
add('<g transform="translate(0 -18) scale(0.5)">'
    '<path d="M18 0 C 22 9, 28 14, 28 20 A 10 10 0 1 1 8 20 C 8 14, 14 9, 18 0 Z" '
    'fill="#E23B6D"/></g>')
add('<text x="42" y="0" font-family="Inter, Segoe UI, Helvetica, Arial, sans-serif" '
    'font-size="40" font-weight="700" fill="#f2f2f4" letter-spacing="0.5">entropybrush</text>')
add('<text x="44" y="30" font-family="Inter, Segoe UI, Helvetica, Arial, sans-serif" '
    'font-size="19" fill="#9a9aa4" letter-spacing="0.3">physics-based painting</text>')
add('</g>')

add('</svg>')

svg = "\n".join(out)
with open("hero.svg", "w") as f:
    f.write(svg)
print("wrote hero.svg", len(svg), "bytes")
