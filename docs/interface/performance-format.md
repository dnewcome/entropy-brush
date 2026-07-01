# Performance format (`.json`) — the machine hand-off contract

A **`TwinPerformance`** is entropybrush's machine-agnostic description of a
painting: an ordered, timestamped list of brush operations. It is what a
downstream machine driver (e.g. the separate paintbot/CNC project) consumes to
reproduce the painting with real paint. See
[ADR 0002](../adr/0002-machine-interface-boundary.md) for the boundary.

Produced by **Record → Save print**; written to `~/entropybrush-exports/print-*.json`.

## Top-level

```jsonc
{
  "format": "entropy-brush-performance",
  "version": 2,
  "canvas": {
    "gridSize": 768,     // sim resolution; op x,y are in cells 0..gridSize
    "sizeMm": 100.0      // intended physical size of the LONGER side (mm).
                         // 0 = unspecified; a design hint the driver may override.
  },
  "ops": [ /* ordered TwinOp objects, ascending t */ ]
}
```

### Coordinate conventions
- `x, y` are in **grid cells**, `0 .. gridSize`. Origin top-left, x→right, y→down.
- Normalize: `nx = x / gridSize`, `ny = y / gridSize` (0..1).
- Physical: `mmPerCell = sizeMm / gridSize`; `x_mm = x * mmPerCell`. (If
  `sizeMm == 0`, the driver supplies the physical size.)

## Ops

Each op has a time `t` (seconds from start) and a `kind`:

| `k` | kind | fields | meaning |
|---|---|---|---|
| 0 | `down`  | `x, y, p` | brush contacts canvas (stroke start) |
| 1 | `move`  | `x, y, p` | brush moves while down |
| 2 | `up`    | —         | brush lifts (stroke end) |
| 3 | `reload`| `r, g, b` | brush recharged with this pigment |

- `p` — **pressure 0..1** — contact force, mapped by the machine to its Z /
  pressure mechanism.
- `r, g, b` — loaded pigment, **linear RGB 0..1**.

```jsonc
{ "t": 0.00, "k": 3, "r": 0.12, "g": 0.20, "b": 0.62 }   // reload (ultramarine)
{ "t": 0.01, "k": 0, "x": 92.0,  "y": 268.0, "p": 0.9 }  // down
{ "t": 0.03, "k": 1, "x": 110.0, "y": 268.0, "p": 0.9 }  // move
{ "t": 0.70, "k": 2 }                                     // up
```

## Driver guidance (paintbot side)

A minimal driver walks the ops in order and:
1. On `reload`, route to the matching paint well and recharge (entropybrush's
   load model predicts *when* a reload is needed; the well location is yours).
2. On `down`/`move`, position `(x,y)` (scaled to mm) and set Z/force from `p`.
3. On `up`, lift.

Notes:
- Ops are pre-interpolated densely enough for the sim; a driver may resample to
  its planner's segment length.
- `t` is wall-clock from recording; use it for pacing if desired, or ignore and
  run at the machine's own feedrate.
- Replaying these ops through entropybrush's sim is **deterministic**, so the
  `.json` fully and reproducibly specifies the intended painting.

## Versioning
- `version: 1` (legacy): `gridSize` at top level, no `canvas`/`sizeMm`. Readers
  should accept both (treat missing `sizeMm` as unspecified).
