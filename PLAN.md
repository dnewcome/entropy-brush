# Plan / TODO

Running list of planned work. See `README.md` and `docs/simulation.md` for the
current model; this file is the "next up" backlog.

## Palette & pigments

- [ ] **Custom color picker for pigment swatches.** Add a small tap area in the
      **upper-right corner** of each pigment swatch that pops up a color picker,
      so a swatch's pigment can be recolored to any custom color (not just the
      four presets). Persist the chosen color for the session.

- [ ] **Add "medium" as a selectable option alongside pigments.** A non-pigment
      medium (linseed/glaze/transparent extender) selectable like a swatch. Loading
      medium thins/extends without adding pigment — lower opacity, more flow/gloss,
      lets you make glazes and washes. Mixing medium into a pigment on the palette
      should reduce its tinting strength (KM concentration), not just lighten it.

- [ ] **Load the brush from the *transition* of mixes on the palette.** Today
      loading samples a single spot. Instead, capture the **sequence/gradient of
      colors the load stroke passes over** on the palette, so the brush picks up
      multiple hues along its length/load and a single canvas stroke then
      **transitions through those colors** as it plays out (like a real brush
      dragged through several piles of paint). Needs the brush load to hold an
      ordered color profile rather than one flat color.
