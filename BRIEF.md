# entropybrush — kickoff brief

- **Problem:** Paint apps stamp textured dabs along a path → fake uniform streaks. We want marks that emerge from a *physically simulated brush* (moving bristles, finite paint load) piling and mixing real paint, to generate PNG + GLB relief assets for a downstream 3D pipeline.
- **Done looks like:** On desktop, drag a brush across the canvas; individual bristles deflect and splay, lay down thick oil paint that piles into impasto relief, deplete their load as they go (drybrush/skip when starved), mix where strokes overlap, and catch an adjustable light — exportable as PNG (color) + GLB (relief mesh).
- **Not now:** Undo, watercolor/acrylic, canvas-tilt UI, layers, real-time perf targets (30fps ok), tablet/stylus build (keep input abstracted).
- **First slice:** Coupled **bristle sim + height-field canvas** — N bristles anchored to a draggable brush head, deflecting/splaying under drag, each with a paint load that transfers (both ways) into a grid storing height + pigment; rendered with normal-map relief lighting. One brush, two pigments, mouse input.
- **Open question (long pole):** Can the coupled bristle↔canvas sim hold ~30fps at usable resolution in Flutter? Resolve via the first slice; if the CPU path is too slow, move the canvas grid step to a `FragmentProgram` ping-pong on the GPU while keeping the (cheap) bristle sim on the CPU.

## Decisions locked in kickoff
- **Platform:** Desktop-first (Linux/macOS/Win), input layer abstracted so stylus pressure/tilt can slot in for a later tablet build.
- **First medium:** Oil / impasto (maps cleanly to a height/depth map → GLB relief).
- **Brush is never a stamp:** it's a real bristle simulation from the first commit.
- **Brush knobs from day one:** bristle count, stiffness, splay, load capacity.
- **Outputs:** PNG (color) + GLB (relief mesh) for a downstream pipeline.
