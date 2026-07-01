# ADR 0001 — Paint representation: field grid vs. Gaussian splats

- **Status:** Accepted
- **Date:** 2026-06-24
- **Context tag:** rendering / simulation substrate

## Context

The painting is currently a **fixed-resolution height-field grid** (`PaintGrid`,
768²): per cell we store paint thickness, surface colour (RGB), wetness, and a
canvas-substrate height. The GPU relief shader samples this grid (bilinearly)
and shades it.

While improving zoom, the limitation surfaced: bilinear sampling smooths the
zoom but **cannot invent detail finer than a grid cell**, so at extreme zoom the
paint reads as soft blobs. The question raised:

> Can we use Gaussian splats instead of texels to smooth things out?

i.e. represent the painting as a set of analytic Gaussian blobs (resolution-
independent) rather than a raster grid.

## Decision

**Keep the field-based grid as the simulation substrate.** Do not move the live
paint representation to Gaussian splats.

If/when crisper zoom is needed, pursue (in order of preference):

1. **Higher simulated resolution** (e.g. 768 → 1280) plus optional **bicubic**
   sampling in the shader. This adds *real* detail to zoom into. Requires
   rescaling default brush dimensions, which are expressed in grid cells.
2. **Re-simulate the recorded stroke vector (`TwinPerformance`) at higher
   resolution** for the zoomed region. The twin op-stream is already
   resolution-independent and replays deterministically, so this is the elegant
   path to genuinely crisp detail at arbitrary zoom.

A **stroke-based Gaussian renderer is acceptable as a future, export-only**
path (see "Future option").

## Rationale

### The physics is field-based
The features that make entropybrush distinctive all operate on a lattice with
locality and neighbours:

- **Wet-paint flow / leveling** — diffusion across neighbouring cells.
- **Kubelka-Munk subtractive mixing** — happens where strokes overlap *in a cell*.
- **Paint displacement (scrape/pile)** — moves height between cells.
- **Drybrush tooth-gating** — compares paint to canvas height at a cell.

Gaussians are sparse, unordered, and overlapping. To run any of this physics on
them you would have to **rasterize the splats back to a grid every frame** —
carrying both representations and getting the worst of both.

### Practical problems with splats as the live representation
- **Unbounded growth.** Every dab adds Gaussians; a real painting is millions of
  overlapping dabs → constant merge/prune just to stay bounded. The grid is
  fixed-size.
- **Compositing / sorting.** Opaque, height-bearing paint needs ordered
  blending; splatting wants depth-sorted accumulation. Awkward for a thick-paint
  height field.
- **Flutter has no compute shaders.** Real splat rasterization (sort + custom
  raster) is not what the `FragmentProgram` path does well; we'd fight the
  framework. (See ADR-worthy note: Flutter exposes fragment shaders, not
  compute.)

### Splats would not add detail anyway
Even rendered as perfect analytic Gaussians, the *information* is bounded by the
resolution we **simulated** at. Splatting the grid's output just interpolates
differently than bilinear — smoother falloff, no new detail. The detail ceiling
is set by simulation resolution, not by the display representation.

## Alternatives considered

| Option | Verdict |
|---|---|
| Gaussian splats as the live sim+render substrate | Rejected — fights field physics, unbounded, no compute in Flutter, no real detail gain |
| Higher grid resolution + bicubic sampling | **Preferred** for crisper *live* zoom |
| Re-simulate stroke vector at higher res for zoomed region | **Preferred** for resolution-independent detail; reuses deterministic replay |
| Stroke-based Gaussian renderer, export-only | Acceptable future option (no physics) |

## Future option: stroke-based Gaussian renderer (export/preview only)

If a *resolution-independent exported asset* is wanted, render the recorded dabs
(`TwinPerformance` ops, or a derived dab list) as Gaussians at arbitrary
resolution, **with no physics**. This is bounded (driven by the recorded stroke
count, not accumulated raster), needs no live simulation, and plays to splats'
strengths. It is a separate renderer, not a change to the simulation core.

## Open question

What are we optimizing for?

- **Smoother live zoom while painting** → raise grid resolution + bicubic.
- **Resolution-independent final output** → stroke-vector re-render (or the
  export-only Gaussian renderer).

The answer selects which preferred path to implement first; until then the live
representation stays the field grid.

## Consequences

- The simulation core (`lib/sim`) remains a grid; all physics keeps its current
  shape.
- "Infinite zoom" is reframed as a *resolution* problem (re-simulate at higher
  detail), not a *representation* problem.
- The deterministic twin op-stream gains importance as the project's
  resolution-independent source of truth.
