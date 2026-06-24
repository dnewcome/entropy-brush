# ADR 0002 — entropy-brush ↔ paintbot machine boundary

- **Status:** Accepted
- **Date:** 2026-06-24
- **Context tag:** scope / integration

## Context

The painting robot ("paintbot") — a brush-wielding CNC machine — is developed as
a **separate project**. entropy-brush should be able to *drive* it, but the
hardware scope must not leak into this repo. We need a clean boundary and a
stable hand-off so the two projects can evolve independently.

## Decision

**entropy-brush emits a machine-agnostic painting artifact; the paintbot project
owns all hardware and consumes the artifact via a file hand-off.**

- The artifact is the recorded **`TwinPerformance`** (`.json`), already produced
  by Record → Save print. It is *intent*, not motion: where the brush went, how
  hard, and in what colour, with timestamps and reload events. See the schema:
  [`docs/interface/performance-format.md`](../interface/performance-format.md).
- **entropy-brush does NOT** contain kinematics, firmware, a G-code dialect,
  Z/pressure-mechanism mapping, paint-well coordinates, or machine calibration.

## Responsibilities

| Concern | entropy-brush | paintbot project |
|---|---|---|
| Brush/paint simulation, the painting | ✅ | |
| Machine-agnostic performance artifact (`.json`) | ✅ | |
| Intended physical size (mm hint) | ✅ (design hint) | may override |
| Kinematics (CoreXY / gantry) | | ✅ |
| Z / pressure mechanism (e.g. voice-coil) mapping | | ✅ |
| Paint-well locations + reload routing | | ✅ |
| Firmware / G-code generation (grbl, etc.) | | ✅ |
| Calibration to the real physical brush | | ✅ |

## Rationale

- **Determinism is the contract.** The performance replays deterministically
  through the sim (verified in `test/twin_replay_test.dart`), so the artifact
  fully and reproducibly describes the painting — the prerequisite for a machine
  to execute it.
- **Firmware/kinematics churn stays out.** grbl quirks, accel limits, well
  geometry, and Z-mechanism details change with the hardware; keeping them in the
  hardware project means entropy-brush doesn't track them.
- **The load model is reusable, not machine-specific.** entropy-brush predicts
  *when* the brush runs dry (reload events in the artifact); the paintbot decides
  *where* the well is and how to route there.

## Interface contract (summary)

- **Format:** `entropy-brush-performance`, versioned. Full schema in
  `docs/interface/performance-format.md`.
- **Coordinates:** op `x,y` in grid cells `0..gridSize`; normalize by `gridSize`
  for `0..1`; multiply by `sizeMm/gridSize` for millimetres.
- **Pressure:** `0..1`, contact force / Z depth (machine maps to its mechanism).
- **Colour:** reload ops carry loaded pigment as linear RGB `0..1`.
- **Hand-off:** a `.json` file (today). A live-stream protocol may be added
  later as an *additional* transport of the same op semantics — still no
  hardware in this repo.

## Consequences

- The `.json` performance is the project's stable public interface; it is now
  self-describing (carries `gridSize` + `sizeMm`).
- A G-code emitter, if built, lives in the **paintbot** project and reads this
  artifact — not here.
- entropy-brush stays a painting + twin tool; the machine stays a machine.
