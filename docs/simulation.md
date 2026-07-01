# The paint simulation

A reference for how entropybrush models a brush, paint, and a canvas. It's a
**height-field grid simulation** (`lib/sim`, Flutter-free) driven by an
abstracted input seam, rendered by a GPU relief shader, and recorded as a
deterministic op stream. This documents the model and the constants; the code is
the source of truth.

Pipeline:

```
INPUT → STROKE OPS → BRUSH (bristles) → DEPOSIT → PAINT GRID (height+colour+wet)
                                                      │
                                         WET FLOW (leveling, drips, drying)
                                                      │
                                      GPU RELIEF RENDER  +  PNG / GLB / STL  +  .json
```

---

## 1. The brush (`sim/brush.dart`)

The brush is **not a stamp** — it's a head carrying `bristleCount` individual
bristles, each a lagging spring-mass tuft with its own paint load.

**Bristle dynamics.** Each bristle has a rest offset (the fan layout, jittered)
and a tip with mass. The tip is pulled toward its (moving, splayed) anchor by a
spring with damping:

```
a = (anchor − tip)·stiffness − vel·damping      (semi-implicit Euler)
```

Fast strokes whip the tips out behind the head (lag), creating brushed marks
rather than stamped ones. `splay` spreads the fan with speed and pressure.

**Contact is a segment, not a point.** Pressure flattens the brush against the
paper, so each bristle's contact runs from a **leading belly** to a **trailing
tip**:

```
contactLen = bristleLength · (0.25 + 0.75·pressure) · bristle.gain
lead       = tip + strokeDir · contactLen
```

Deposition is front-weighted (≈65% at the wider belly, ≈35% at the narrower
tip), so strokes get a comet shape. The trailing tip also **plows** wet paint:
`grid.scrape` removes a little ahead of the tip and `grid.pile` deposits it
behind (conservative), building ridges (`displacement`).

**Per-bristle character.** Each bristle has a random `gain` (0.55–1.45, how much
it lays / how fast it drains) and `rscale` (0.7–1.3, track width), so the stroke
breaks into individual striations and ragged edges.

### Load, mileage, drybrush

Each bristle holds a finite load. Deposition per step:

```
loadFrac  = load / loadCapacity
gate      = clamp(loadFrac · 3, 0, 1)              // steady, then taper to dry
dwellBoost= 1 + dwellBuildup · dwell               // slow strokes lay more (§1.1)
laid      = depositRate · pressure · dt · gate · gain · dwellBoost
consumed  = laid · (1 − 0.9·mileage)               // mileage decouples drain
load     −= consumed
```

`mileage` lets a load cover a useful distance before drying (drain ≪ paint laid).
As load runs low the stroke falls to **drybrush / scumble** — see tooth gating
below. **Infinite paint** tops up load (and colour) every step.

### Dwell — velocity → volume (`sim/brush.dart`, `paint_controller.dart`)

Stroke speed only affects *how much paint is laid*, never drips directly:

```
dwell = kRef / (speed + kRef)            kRef = 700 grid-px/s   (slow→1, fast→0)
```

Live, `dwell` is computed from real time; on replay it's reconstructed from op
timestamps, so the twin stays faithful. **`dwellBuildup`** scales the boost
(tunable). On lift, `layPool` releases a pool at the dwell point (drawn from the
remaining load) — the classic origin of an end-of-stroke drip.

> A more principled version (deposit ∝ *time-in-contact*) is on the roadmap; the
> dwell-boost + terminal-pool are the current approximation.

### Pour mode — no brush (`paint_controller.dart`)

A toggle that bypasses the bristle brush entirely: while the pen is down it lays
a **fully-wet liquid bead** at the pen tip every frame (`grid.deposit` with full
coverage, so no drybrush tooth gating). Held in place the bead widens to a cap
and mounds a puddle; moving, it draws a thick wet trail — like squeezing paint
straight from the bottle. Because the paint lands wet, it immediately obeys wet
flow: it self-levels, and with **gravity drips** or **spin** on it runs or
flings. Its runniness is the medium's (Viscosity / Flow), so a runny profile
pours like ink and a stiff one like a thick ribbon. The pen path is still
recorded as a stroke, so the poured toolpath is captured for the twin (the
poured *deposition* is not yet reproduced on replay — a known gap).

---

## 2. The paint grid (`sim/paint_grid.dart`)

The canvas is a set of `Float32List`s, one value per cell:

| Field | Meaning |
|---|---|
| `thickness` | paint relief (height), arbitrary ~mm units |
| `r, g, b` | top-surface pigment colour (linear 0..1) |
| `wet` | wetness 0..1 — only wet paint flows; it dries and sets |
| `canvasHeight` | procedural substrate relief (linen tooth), persists through Clear |

Rendered/exported height is `canvasHeight + thickness`.

### Deposition into a cell

A bristle lays a soft round dab (quadratic falloff). Per cell:

```
add  = w · k · body · lumpMul · toothGate        // height added
```

- **`body`** — paint thickness/opacity (buttery vs runny); scales pile height
  and goes into the exported mesh.
- **`lumpiness`** — a *canvas-locked* fbm noise field modulates the height, so
  repeated strokes deepen the same tooth (reads as paint texture, not flicker).
- **Tooth gating (drybrush).** `coverage = loadFrac·(0.45 + 0.55·pressure)`; the
  deposit is gated by a smoothstep on the canvas tooth so a loaded brush floods
  the valleys but a dry one catches only the peaks → scumble, canvas showing
  through.

Each deposit marks the cell **wet** (`_wetTouch`).

### Colour mixing — Kubelka-Munk (subtractive)

Pigments mix like paint (blue + yellow = green, not grey). Per channel, treat
the reflectance as a yield of absorption/scattering and blend in K/S space:

```
ks(r)   = (1−r)² / (2r)
unks(ks)= 1 + ks − √(ks² + 2ks)
mix(base, pig, t) = unks( ks(base)·(1−t) + ks(pig)·t )
```

Used on deposit, in the mixing palette, and in wet-on-wet flow.

### Helpers
`scrape` (remove paint + carry colour), `pile` (conservatively add paint), and
`sampleColor` (read-only) support plowing and the brush's wet-on-wet pickup.

---

## 3. Wet-paint flow (`flowStep`)

Each frame the controller runs `flowStep` over the **wet bounding box** only
(localized cost). It combines leveling, gravity drips, and drying, all
**conservative** (paint is moved, never created/destroyed).

**Joint outflow budget (why it stays conservative).** Leveling and gravity each
want to draw paint out of a cell. Individually each term is bounded, but their
*sum* can exceed what the cell holds — and the clamp that stops thickness going
negative would then turn the over-draw into *created* paint at the neighbours,
raising their mobile paint and feeding back until the height field explodes to
`Infinity`. So each cell first **collects all the outflow it wants** (four
downhill leveling pushes + both gravity axes), and if the total exceeds what it
holds, scales the whole set down by one factor — nothing leaves a cell that
wasn't there. Leveling is therefore a downhill *push* to the 4-neighbourhood
(equivalent to the old pairwise form) so all of a cell's outflow lives in one
place and can be budgeted together.

### Leveling (surface tension / oozing)

Wet paint diffuses to even out height, carrying colour **and** wetness with the
mass (mass-weighted, via the `inW` buffer) so pigment travels with the paint and
there's no detached outline:

```
flux(i→j) = k · gate · (h_i − h_j)        k ≤ 0.2,  gate = wetness of uphill cell
colour_j, wet_j  ← mass-weighted blend toward the incoming paint
```

Strength is the **Flow (leveling)** slider (mapped to per-frame substeps).

### Gravity drips — yield-stress fluid

Paint is a **Bingham plastic**: it doesn't flow until gravity overcomes the yield
stress. Only thickness **above** `dripYield` is mobile; a `dripYield`-thick film
clings behind, which depletes the run and ends it (length ∝ available paint, not
just drying):

```
mobile = thickness − dripYield                     (≤0 ⇒ holds, no drip)
amt    = |gravComp| · mobile · wet     capped at mobile · 0.7
```

World-down gravity is projected onto the **tilted canvas plane** to get the grid
drip vector — full when face-on, zero when pitched flat, rotating with roll:

```
gravX = sin(canvasRoll) · cos(tiltX) · base
gravY = cos(canvasRoll) · cos(tiltX) · base        base = 1.3·gravityStrength / iters
```

**Viscosity** (`profile.viscosity`) resists all motion: leveling rate `/= visc`,
effective yield `= dripYield · visc`, and the drip flow rate slows. So stiff
high-viscosity paint holds its shape and barely drips; runny low-viscosity paint
oozes and sheets down. **Drip wander** adds a smooth low-frequency lateral noise
(random phase per canvas) so drips meander left/right and don't form the exact
same shape twice.

**Gravity must dominate leveling** or paint bleeds isotropically instead of
running down. So when a **directional body force** (gravity drips or spin) is
on, leveling is suppressed to `0.03`. (Verified: drip region aspect h/w ≈ 2.3 vs
isotropic bleed ≈ 1.2.)

### Spin — centrifugal + Coriolis

Gravity is one special case of a **body force**: a uniform drift vector. Spinning
the canvas replaces it with a **position-dependent** one. In the canvas's
co-rotating frame a cell at offset **r** from the pivot feels centrifugal
acceleration ω²·**r** pointing straight out, so the outward drift is simply
`spinCf · (x−cx, y−cy)` — zero at the pivot, growing to the rim. A Coriolis term
(∝ ω, perpendicular, signed by spin direction) curls the outward streaks into
spirals like real spin art:

```
dgx = gravX + spinCf·(x−cx) + spinCor·(y−cy)
dgy = gravY + spinCf·(y−cy) − spinCor·(x−cx)     spinCf ∝ ω²,  spinCor ∝ ω
```

That combined `(dgx, dgy)` runs through the *same* yield-stress + joint-budget
path as gravity, so only mobile wet paint above the film flings out, and the
step stays conservative no matter how hard you spin. Gravity and spin add, so a
tilted spinning canvas both runs *and* flings. Because centrifugal force is
defined in the canvas plane it needs **no tilt projection** (unlike gravity).

The canvas also **visibly rotates** while spinning: a live `_spinAngle`
accumulates at the spin rate and rides on top of the user's `canvasRoll`
(`displayRoll = canvasRoll + _spinAngle`), used for both projection and pointer
mapping so the fling is tied to a turning canvas rather than paint sliding on a
still one. Speed and substep count scale with the rate so higher speeds fling
faster (each flow substep can only move a bounded fraction of a cell — the
conservation cap — so more substeps per frame = paint reaches the rim sooner).
(Verified in `centrifugal_test`: an off-centre blob migrates to the rim, a
centred blob flings into a ring while its centroid stays pinned at the pivot,
mass exactly conserved.)

### Drying — volume-dependent

Bigger volumes take longer to set, so drips of thick paint run longer while thin
trails dry and stop:

```
wet_i ·= exp( −dt / (dryTime · (1 + thickness_i · 8)) )
```

A drip front inherits its (drying) source's wetness through the mass-weighted
advection, so the run naturally ends — no force-wetting.

---

## 4. Rendering (`shaders/relief.frag`, `render/relief_renderer.dart`)

A Flutter `FragmentProgram` shades the canvas as oil paint:

- **Normals** reconstructed from the height field by finite differences (16-bit
  height packed across R+G, manually bilinear-decoded so zoom stays smooth).
- **Cavity ambient occlusion** — crevices between strokes darken (tactile depth).
- **Hemispheric ambient + key + fill** light, with a movable key direction.
- **Wet specular + broad sheen + fresnel** edge for an oily look.
- **Albedo** bilinear-sampled and saturation-adjusted.
- **Zoom/pan in UV** (not a magnified raster), so it stays crisp at any zoom.

Flutter exposes fragment shaders but **not compute**, so the simulation runs on
the CPU and the GPU only shades — see
[ADR 0001](adr/0001-paint-representation-grid-vs-splats.md).

## 5. The 3D canvas slab (`ui/slab_view.dart`, `ui/slab_painter.dart`)

The canvas is a **3D slab with thickness**: the painting (rendered flat to a
cached image) is textured onto the top face; back + side faces give depth.
Pan/zoom/tilt/roll move the whole slab. Because a perspective projection of a
plane is a homography, mapping a screen click back to the canvas (for painting)
is an exact **inverse homography** — round-trip verified in `slab_view_test`.

---

## 6. Parameters

| Group | Param | Default | Effect |
|---|---|---|---|
| Brush | bristleCount | 80 | hairs in the fan |
| | headRadius | 14 | fan size (px) |
| | stiffness / damping | 240 / 14 | tip lag & whip |
| | splay | 0.9 | fan spread with speed |
| | loadCapacity | 1.6 | paint a full brush holds |
| | mileage | 0.7 | distance a load covers (drain vs lay) |
| | depositRate | 2.2 | paint laid per second |
| | bristleLength | 9 | contact-segment length (flatten) |
| | displacement | 0.15 | trailing-tip plowing |
| | dwellBuildup | 1.2 | velocity → extra volume (drip cause) |
| | pourMode | off | pen pours wet liquid paint, no brush |
| Paint | body | 1.0 | pile height / opacity |
| | viscosity | 1.0 | flow resistance: slower leveling, higher drip yield, slower drips |
| | lumpiness | 0.25 | tooth/clump texture |
| | grain / opacity | 0.12 / 1.0 | tooth scale / coverage |
| Wet flow | flowRate | 0.4 | leveling/oozing strength |
| | dryTime | 3.0 | seconds to set (×volume factor) |
| | gravityDrips | off | world-down drips |
| | gravityStrength | 1.0 | drip speed |
| | dripYield | 0.07 | surface-tension threshold (drip start) |
| | dripWander | 0.4 | lateral meander so drips aren't identical |
| | spinning | off | centrifugal spin — flings wet paint to the rim |
| | spinSpeed | 1.5 | how fast the canvas spins (0 = stopped) |
| | spinCW | off | spin direction (flips the spiral handedness) |
| Canvas | canvasAmplitude | 0.08 | substrate tooth depth |
| | canvasThicknessFrac | 0.06 | slab edge thickness |
| Light | occlusion / gloss / fill / saturation | 0.6 / 0.5 / 0.4 / 1.18 | material |
| View | tilt (±1.309), zoom (≤12), pan, roll | — | 3D slab pose |
| Export | sizeMm / reliefMm / baseMm / resolution | 100 / 6 / 2 / 256 | real-world mesh |

---

## 7. Properties & verification

- **Conservation** — deposition, plowing, leveling, drips, and drying all move
  or transform paint without spurious creation/loss (tested). The wet-flow step
  enforces this with a per-cell joint outflow budget, so even runny paint on a
  steeply tilted canvas can't manufacture mass or blow up to `Infinity`
  (`drip_blowup_test`: 600 aggressive steps stay finite and mass-exact).
- **Crash safety** — the height/albedo encoders reject non-finite values
  (`NaN`/`Infinity` are clamped, not fed to `.round()`), so a single bad cell can
  never freeze the renderer. (Defence in depth behind the conservation invariant.)
- **Determinism** — the same op stream reproduces the same painting; dwell is
  derived from recorded timestamps so replay/print stays faithful
  (`twin_replay_test`). (Wet flow is real-time-driven, so the in-app *preview*
  replay is approximate; the authoritative artifact is the op stream.)
- **Headless tests** (`dart run test/<name>.dart`) cover the brush, profile,
  mixing, wet flow, drips (yield, directional, colour), exports (watertight
  STL), the twin, the slab projection, and input parsing.

See also: [ADR 0001](adr/0001-paint-representation-grid-vs-splats.md) (grid vs
splats), [ADR 0002](adr/0002-machine-interface-boundary.md) (machine boundary),
[`MODELING.md`](../MODELING.md) (learning the model from real strokes).
