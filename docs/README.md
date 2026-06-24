# Design docs

Architecture Decision Records (ADRs) and design notes for entropy-brush.

## ADRs

- [0001 — Paint representation: field grid vs. Gaussian splats](adr/0001-paint-representation-grid-vs-splats.md)
  — why the paint stays a simulated height-field grid rather than moving to
  Gaussian splats, and how to get crisper zoom instead (higher resolution /
  stroke-vector re-render).
