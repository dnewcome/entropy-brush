# entropy-brush

A physics-based oil painting program in Flutter. Not a noise-smear paint app —
the brush is a real simulated object, the paint is a fluid that piles, flows,
and dries, and the canvas is a 3D relief surface you can light and tilt.

The longer-term goal: use this as the digital twin / front-end for a brush-
wielding CNC machine (a 3-axis Shapeoko), so a painting performed here — live or
recorded — can be replayed with real paint on real canvas.

## What's simulated

- **Bristle brush, not a stamp.** The brush head carries dozens of individual
  bristles modelled as lagging spring-mass tufts. They deflect, splay, trail,
  and each carries a finite, per-hair paint load — so marks emerge from moving
  bristles instead of a textured rubber stamp. The contact is a *segment* with
  length: pressure flattens the brush against the paper, deposition leads at the
  belly and the tips trail behind, plowing wet paint into ridges.
- **Finite paint load with a useful "mileage."** Load drains as you paint and
  the brush goes to drybrush/scumble, catching only the canvas tooth peaks when
  it runs low. A mileage control decouples how long a load lasts from how much
  paint it lays. Optional **infinite paint** for continuous work.
- **Wet paint flow.** Fresh paint is a fluid: it levels, oozes, and bleeds
  wet-on-wet, then dries and sets so impasto is preserved. Strictly
  conservative — paint is moved, never created or destroyed.
- **Subtractive colour mixing (Kubelka-Munk).** Blue + yellow makes green, not
  muddy grey — on the canvas and on a squeeze-paint **mixing palette**.
- **Height-field canvas with Perlin tooth.** Paint thickness + a procedural
  linen substrate make a real relief surface.
- **GPU relief render.** A Flutter `FragmentProgram` reconstructs normals from
  the height field and shades with cavity ambient occlusion, hemispheric +
  fill light, and a wet glossy specular/sheen/fresnel — so impasto reads as
  tactile, oily paint. Tilt, zoom, and a movable light included.

## Exports

- **PNG** — the shaded colour render.
- **GLB** — a relief mesh (height-displaced grid with vertex colours) for a
  downstream 3D pipeline.
- **`.json` "prints"** — a recorded painting *performance* (timestamped stroke
  ops + pressure + reloads) that replays deterministically through the sim, and
  is the basis for future G-code generation.

Outputs are written to `~/entropy-brush-exports`.

## Webcam input (experimental)

A Python sidecar (`tools/hand_tracker.py`, MediaPipe Hands) streams hand
position + pinch over UDP into the app's input seam, so you can paint by pinch-
ing in front of a webcam. The same seam is where a depth-camera arm tracker
will plug in.

```bash
pip install mediapipe opencv-python
python3 tools/hand_tracker.py   # then toggle "Start webcam" in the app
```

## Running

Desktop-first (developed on Linux).

```bash
flutter pub get
flutter run -d linux      # or macos / windows
```

The simulation layers (`lib/sim`, `lib/twin`, `lib/export`) have no Flutter
dependencies, so the physics is covered by headless checks runnable directly:

```bash
dart run test/wet_flow_test.dart
dart run test/twin_replay_test.dart
# ...etc
```

## Status

Prototype, evolving quickly. See `BRIEF.md` for the original kickoff intent.

🤖 Built with [Claude Code](https://claude.com/claude-code)
