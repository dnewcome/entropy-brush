# Design docs

Architecture Decision Records (ADRs) and design notes for entropy-brush.

## ADRs

- [0001 — Paint representation: field grid vs. Gaussian splats](adr/0001-paint-representation-grid-vs-splats.md)
  — why the paint stays a simulated height-field grid rather than moving to
  Gaussian splats, and how to get crisper zoom instead (higher resolution /
  stroke-vector re-render).
- [0002 — entropy-brush ↔ paintbot machine boundary](adr/0002-machine-interface-boundary.md)
  — the painting tool emits a machine-agnostic performance artifact; the
  separate paintbot project owns all hardware and consumes it.

## Interface specs

- [Performance format (`.json`)](interface/performance-format.md) — the machine
  hand-off contract: schema, units, op kinds, driver guidance.

## Research notes

- [`MODELING.md`](../MODELING.md) — learning the brush/paint model from real
  strokes: what to capture, the force problem, and using the robot as the
  data-collection rig.
