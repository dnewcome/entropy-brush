import 'dart:math' as math;
import 'package:entropy_brush/sim/paint_grid.dart';

/// Pour mode lays flowing liquid paint straight onto the canvas — no brush, no
/// drybrush gating. This mirrors PaintController._pour (grid.deposit marks the
/// cells wet=1 and default coverage floods the tooth) and checks the result is
/// genuinely liquid: a growing, fully-wet puddle that then levels and, under
/// gravity, runs.
void main() {
  final g = PaintGrid(160, 160);
  const double cx = 80.0, cy = 60.0;

  // 40 frames of a held pour at one spot (widening bead, like _pour).
  double accum = 0;
  const double vol = 0.9;
  for (int f = 0; f < 40; f++) {
    accum += vol;
    final double r = math.min(11.0, 4.0 + math.sqrt(accum) * 1.2);
    g.deposit(cx, cy, r, vol, 0.15, 0.25, 0.7);
  }

  double mass = 0;
  for (final t in g.thickness) {
    if (t > 0) mass += t;
  }
  final double wetCenter = g.wet[cy.round() * g.width + cx.round()];

  double peak0 = 0;
  int fp0 = 0;
  for (final t in g.thickness) {
    if (t > peak0) peak0 = t;
    if (t > 0.001) fp0++;
  }

  // Held pour mounds a puddle; released, it levels like liquid.
  for (int s = 0; s < 120; s++) {
    g.flowStep(1 / 60, flow: 0.2, dryTime: 1000);
  }
  double peak1 = 0;
  int fp1 = 0;
  for (final t in g.thickness) {
    if (t > peak1) peak1 = t;
    if (t > 0.001) fp1++;
  }

  print('poured mass=${mass.toStringAsFixed(2)}  '
      'wet@center=${wetCenter.toStringAsFixed(2)}');
  print('level: peak ${peak0.toStringAsFixed(3)} -> ${peak1.toStringAsFixed(3)}  '
      'footprint $fp0 -> $fp1');

  final bool laysPaint = mass > 25; // ~40*0.9 minus edge falloff
  final bool liquid = wetCenter > 0.9;
  final bool flows = peak1 < peak0 && fp1 > fp0;

  print('pours a real amount:       $laysPaint');
  print('poured paint is wet:       $liquid');
  print('poured paint flows/levels: $flows');

  if (!laysPaint) throw StateError('pour laid too little paint');
  if (!liquid) throw StateError('poured paint not wet');
  if (!flows) throw StateError('poured paint did not flow');
  print('PASS');
}
