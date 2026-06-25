# entropy-brush

A physics-based oil painting program in Flutter. Not a noise-smear paint app —
the **brush is a real simulated object**, the **paint is a fluid** that piles,
flows, and dries, and the **canvas is a 3D relief surface** you can light, tilt,
and export as a printable mesh.

The longer-term goal: use this as the digital twin / front-end for a brush-
wielding CNC machine (a 3-axis Shapeoko), so a painting performed here — live or
recorded — can be replayed with real paint on real canvas.

> Status: working prototype, evolving fast. Desktop-first (developed on Linux).

---

## What makes it different

Most paint programs drag a textured stamp along a path. entropy-brush simulates
the actual *causes* of a brushstroke:

- **Bristle brush, not a stamp.** The head carries dozens of individual bristles
  modelled as lagging spring-mass tufts — they deflect, splay, and trail, and
  each carries a finite, per-hair paint load. Marks *emerge* from moving
  bristles. The contact is a **segment with length**: pressure flattens the
  brush against the paper, the belly leads with the heavy paint, and the tips
  trail behind, **plowing wet paint into ridges**.
- **Finite paint load + "mileage."** Load drains as you paint; the brush falls
  to drybrush/scumble, catching only the canvas tooth peaks when it runs low. A
  *mileage* control decouples how far a load lasts from how much it lays down.
  Toggle **infinite paint** for continuous work.
- **Wet paint flow (the fluid sim).** Fresh paint levels, oozes, and bleeds
  wet-on-wet, then dries and *sets* so impasto is preserved. Strictly
  conservative — paint is moved, never created or destroyed.
- **Subtractive colour mixing (Kubelka-Munk).** Blue + yellow makes green, not
  muddy grey — on the canvas and on a **squeeze-paint mixing palette** (press &
  hold to extrude a blob, drag to mix, dip the brush to load).
- **Height-field canvas with Perlin tooth.** Paint thickness + a procedural
  linen substrate make a genuine relief surface.
- **GPU relief render.** A Flutter `FragmentProgram` reconstructs normals from
  the height field and shades with **cavity ambient occlusion** (crevices
  darken), hemispheric + fill light, and a **wet glossy specular / sheen /
  fresnel** — so impasto reads as tactile, oily paint. Crisp at any zoom
  (UV-space zoom + bilinear sampling, not raster magnification).

## Controls

- **Paint:** drag on the canvas.
- **Zoom:** mouse wheel (anchored on the cursor). Pan/zoom/tilt also have
  sliders.
- **Orbit:** drag the gizmo in the canvas's top-right (double-tap to reset).
- **Light & material:** sliders for light direction, relief, cavity shadow, wet
  gloss, fill, saturation.
- **Mixing palette:** press & hold to squeeze paint, drag to mix, **Load brush**
  to dip.
- **Record / Replay:** capture a painting performance and replay it
  deterministically (a "print").

## Exports

All written to `~/entropy-brush-exports`:

| Format | What | For |
|---|---|---|
| **PNG** | the shaded colour render | sharing / reference |
| **GLB** | colour relief mesh (vertex-coloured) | 3D viewers / render pipelines |
| **STL** | **watertight** relief solid (top + base + walls) | 3D printing / CNC |
| **`.json`** | recorded stroke *performance* | replay, and future G-code |

GLB/STL export at **real-world millimetre scale** — set size, relief height,
base thickness, and mesh resolution, and the STL drops straight into a slicer at
true size.

## Architecture

One pipeline with pluggable ends:

```
INPUT SOURCE        →   STROKE STREAM       →   SIMULATION (the twin)   →   OUTPUTS
mouse / stylus          x, y, pressure,         bristles + paint grid       screen (GPU relief)
webcam (MediaPipe)      timestamp               wet flow, K-M mixing        PNG / GLB / STL
(depth cam later)                               + deterministic recorder    .json "print"
```

- `lib/sim` — the brush, the height-field `PaintGrid` (deposit, scrape/pile,
  wet flow), paint profile, noise. **No Flutter dependency.**
- `lib/twin` — the input seam, the recorder/replay, and the portable
  `TwinPerformance`. **No Flutter dependency.**
- `lib/export` — PNG/GLB/STL writers.
- `lib/render`, `lib/ui` — the `FragmentProgram` relief renderer and the app.

Because the sim and twin layers are Flutter-free, the physics is covered by
**headless tests you can run directly** — and the stroke recording **replays
deterministically** (same ops → same painting), which is the prerequisite for
ever driving a real machine.

```bash
dart run test/wet_flow_test.dart        # conservation, leveling, drying
dart run test/twin_replay_test.dart     # determinism + JSON round-trip
dart run test/stl_export_test.dart      # STL is watertight
dart run test/expressive_brush_test.dart
# ...and others in test/
```

## Webcam input (experimental)

A Python sidecar (`tools/hand_tracker.py`, MediaPipe Hands) streams hand
position + pinch over UDP into the input seam — paint by pinching in front of a
webcam. The same seam is where a depth-camera arm tracker will plug in.

```bash
pip install mediapipe opencv-python
python3 tools/hand_tracker.py   # then toggle "Start webcam" in the app
```

## SpaceMouse (6DOF view navigation)

A 3Dconnexion SpaceMouse drives the **view** — translate to pan, push/pull to
zoom, tilt/twist to orbit — so your non-dominant hand navigates while you paint.
Same UDP-sidecar pattern. On Linux it reads from the **spacenavd** daemon's
socket (stdlib only, no HID permissions needed):

```bash
sudo apt install spacenavd && sudo systemctl enable --now spacenavd
python3 tools/spacemouse.py     # --debug to watch axes; toggle in the app
```

## Running

```bash
flutter pub get
flutter run -d linux            # or macos / windows
```

A visible **build tag** in the top-left of the control panel tells you which
build you're running.

## Driving a machine

entropy-brush is the painting + twin tool; the **paintbot hardware is a separate
project**. The boundary is deliberate: this repo emits a **machine-agnostic
performance artifact** (the `.json` print) and contains *no* kinematics,
firmware, or G-code. A machine driver consumes that artifact and owns all
hardware. See [ADR 0002](docs/adr/0002-machine-interface-boundary.md) and the
[performance-format contract](docs/interface/performance-format.md).

## Roadmap

- **Time-based deposition** — deposit `∝ time-in-contact` instead of
  per-distance, so velocity → volume falls out from first principles: fast
  strokes lay thin, slowing builds up, and holding the brush still pools paint
  (drips emerge naturally). Would retire the current dwell-boost and
  terminal-pool approximations. (Deferred; bigger change — deposition becomes
  real-time-driven, including while the brush is stationary.)
- **Depth-camera arm tracking** → live painting from real arm motion.
- **Brush calibration** so the sim predicts the physical brush.
- Higher-resolution / stroke-vector re-render for infinite-zoom detail
  (see ADR 0001).
- **Drip fingering/rivulets** — thickness-dependent instability so runs
  self-focus into narrowing teardrops instead of smooth widening runs.
- *(In the separate paintbot project:)* G-code emitter that reads the `.json`
  performance and drives the machine.

## Notes

- Flutter exposes fragment shaders but **not compute shaders**, so the
  simulation runs on the CPU and the GPU only shades the relief. This shaped
  several design decisions — see [`docs/`](docs/).

## Design docs

Architecture decisions live in [`docs/`](docs/), e.g.
[ADR 0001: paint representation (grid vs. Gaussian splats)](docs/adr/0001-paint-representation-grid-vs-splats.md)
and [ADR 0002: the machine-driver boundary](docs/adr/0002-machine-interface-boundary.md).

- `BRIEF.md` — the original kickoff intent.
- [`MODELING.md`](MODELING.md) — how we might learn the brush/paint model from
  real strokes (and why the robot is the data-collection rig).

---

🤖 Built with [Claude Code](https://claude.com/claude-code)
