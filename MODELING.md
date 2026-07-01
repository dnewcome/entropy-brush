# MODELING.md — learning the brush/paint model from real data

How we might replace (or augment) the hand-tuned brush–paint–canvas physics in
entropybrush with a model fit to **real** brushstrokes. This is a research
direction, gated on the paintbot hardware; captured here so the plan survives.

## What we'd be learning (three separable sub-problems)

1. **Bristle kinematics** — how the tuft deflects, splays, and trails under load
   and drag. (Currently hand-modelled as lagging spring-mass tufts.)
2. **Paint transfer** — how much paint deposits / lifts given contact, load, and
   speed: drybrush, scumble, wet-on-wet pickup, mixing. *The messy, high-value
   part.*
3. **The resulting mark** — the footprint geometry + surface color + relief
   height left behind.

The ML payoff is largest in (2) and (3); (1) is already adequate physics.

## The crux: the data problem, and the hidden variable

To learn any of this you need **brush state + the resulting mark, registered in
space and time.** Position and the mark are observable with cameras. The thing
vision *cannot* give you directly is **contact force / pressure** — and that is
the most important single input. Inferring force from mark darkness is circular.

So the real fork is not "camera vs. sensors" — it's **how to capture force.**

| Approach | Gives you | Misses |
|---|---|---|
| **Camera only** (incl. dyed/colored bristles) | Bristle shape/deflection over time (good for sub-problem 1) | Force, load, how much paint moved |
| **Sensorized mount** — 6-axis force/torque at the *ferrule/holder* | Contact force + lateral drag | Adds cost; keep it off the bristles |
| **Robot rig** (recommended) | Exact X/Y/velocity, commanded Z, and **voice-coil current ≈ force** | (need to scan the result) |

**Do not sensorize the bristles** — fragile, and it changes their dynamics.
Keep the bristles passive; put instrumentation in the mount and use cameras for
shape + result.

## Why the robot is the unlock

The key insight: **the digital twin and the data-collection apparatus are the
same hardware.** With the brush on the CNC:

- **Auto-sweep a labeled dataset**: vary speed × pressure × load × brush angle ×
  paint over hundreds/thousands of controlled, repeatable strokes.
- **Capture the mark**: *color* with a calibrated, flat-lit camera; *relief
  height* with **photometric stereo** — which we're already set up for, since
  the app/rig has movable lighting (multi-light shots → surface normals →
  height; no expensive scanner needed).
- **Capture bristle shape**: a side camera with **colored bristles**, filmed
  simultaneously.
- **Close the loop**: model predicts → robot paints → scan → compare → refine.

## How to train it (recommended order)

1. **System identification first — not a black box.** The sim is already
   parameterized (deposit rate, mileage, coverage curve, displacement,
   Kubelka-Munk pigment constants, flow/dry rates). Make those fit-able and
   **optimize them to match real scanned strokes.** Keeps physical
   interpretability, integrates with everything built, needs little data.
2. **Add a learned residual where physics falls short.** A small net that
   corrects the sim's predicted mark — e.g. an image-to-image patch model:
   *(local canvas patch + brush footprint + force) → new patch (height +
   color)*. Physics provides the prior; the net learns the unmodeled remainder
   (worn-brush footprints, odd splay textures). Hybrid > pure black box.
3. **Two-stage capture matches a two-stage model**: colored-bristle side video →
   fit bristle mechanics; robot force + canvas scan → fit/learn deposition.

## Direct answers

- **"Would a camera looking at colored bristles work?"** Yes — for **bristle
  deformation**, it's the right tool. By itself it can't teach paint transfer
  (no force, no measure of paint moved).
- **"Sensors on the bristles?"** No — sensorize the **mount** (force/torque), or
  better, use the **robot's Z command + voice-coil current** as the force
  signal. Bristles stay passive.

## A quiet advantage we already have

The **deterministic twin replay**: run the exact recorded stroke in sim and on
the robot and diff the results — that diff *is* the training signal for the
residual model. The record → replay → compare scaffolding already built is the
basis for sim-to-real learning. (See `docs/interface/performance-format.md`.)

## Practical gotchas

- **Registration/calibration** — align brush-cam, canvas scan, and force in
  space and time.
- **Non-stationarity** — paint dries and changes; capture time series for the
  flow/drying model, and control paint batch / humidity for repeatability.
- **Sim-to-real gap** — start with system ID (small, interpretable) before
  committing to a data-hungry net.

## Status

Direction only — data collection waits on the paintbot. First concrete step once
hardware exists: a `tools/calibrate/` routine that sweeps stroke parameters,
scans results (photometric stereo via the movable light), and fits the sim
parameters by system identification.
