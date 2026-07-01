import 'dart:math' as math;
import 'package:entropy_brush/sim/paint_grid.dart';

/// Spinning the canvas should fling wet paint toward the rim (centrifugal
/// force ∝ ω²·r, outward from the pivot), while the pivot itself stays a fixed
/// point. Reuses the same yield-stress + joint-budget flow path as gravity, so
/// it must also stay finite and mass-conservative.

const double cx = 80.0, cy = 80.0;

double mass(PaintGrid g) {
  double t = 0;
  for (final th in g.thickness) {
    if (th > 0) t += th;
  }
  return t;
}

/// Thickness-weighted mean distance from the pivot.
double radialCom(PaintGrid g) {
  double t = 0, wr = 0;
  for (int y = 0; y < g.height; y++) {
    for (int x = 0; x < g.width; x++) {
      final double th = g.thickness[y * g.width + x];
      if (th > 1e-6) {
        final double dx = x - cx, dy = y - cy;
        t += th;
        wr += th * math.sqrt(dx * dx + dy * dy);
      }
    }
  }
  return t > 0 ? wr / t : 0;
}

/// Thickness-weighted centroid.
List<double> centroid(PaintGrid g) {
  double t = 0, wx = 0, wy = 0;
  for (int y = 0; y < g.height; y++) {
    for (int x = 0; x < g.width; x++) {
      final double th = g.thickness[y * g.width + x];
      if (th > 1e-6) {
        t += th;
        wx += th * x;
        wy += th * y;
      }
    }
  }
  return t > 0 ? [wx / t, wy / t] : [cx, cy];
}

void spin(PaintGrid g, {int steps = 200, double rate = 1.5}) {
  final double cf = 0.02 * rate * rate;
  final double cor = 0.010 * rate;
  for (int s = 0; s < steps; s++) {
    g.flowStep(1 / 60,
        flow: 0.03,
        dryTime: 1000,
        spinCf: cf,
        spinCor: cor,
        spinCx: cx,
        spinCy: cy);
  }
}

void main() {
  // 1. Off-centre blob: should migrate OUTWARD (toward the +x rim it sits on).
  final off = PaintGrid(160, 160);
  off.pile(cx + 20, cy, 8, 6.0, 0.2, 0.4, 0.8);
  final double r0 = radialCom(off);
  final double x0 = centroid(off)[0];
  final double m0 = mass(off);
  spin(off);
  final double r1 = radialCom(off);
  final double x1 = centroid(off)[0];

  bool finite = true, peakOk = true;
  for (final th in off.thickness) {
    if (!th.isFinite) finite = false;
  }
  final double m1 = mass(off);

  // 2. Centred blob: flings into a ring but its centroid stays at the pivot.
  final cen = PaintGrid(160, 160);
  cen.pile(cx, cy, 8, 6.0, 0.2, 0.4, 0.8);
  final double cr0 = radialCom(cen);
  spin(cen);
  final double cr1 = radialCom(cen);
  final List<double> cc = centroid(cen);
  final double drift = math.sqrt(
      (cc[0] - cx) * (cc[0] - cx) + (cc[1] - cy) * (cc[1] - cy));

  print('off-centre  radialCOM ${r0.toStringAsFixed(1)} -> '
      '${r1.toStringAsFixed(1)}   meanX ${x0.toStringAsFixed(1)} -> '
      '${x1.toStringAsFixed(1)}');
  print('centred     radialCOM ${cr0.toStringAsFixed(1)} -> '
      '${cr1.toStringAsFixed(1)}   centroid drift ${drift.toStringAsFixed(2)} px');
  print('mass ${m0.toStringAsFixed(2)} -> ${m1.toStringAsFixed(2)}   '
      'finite: $finite');

  final bool movesOut = r1 > r0 + 3 && x1 > x0 + 2;
  final bool fringsRing = cr1 > cr0 + 3;
  final bool pivotFixed = drift < 3.0;
  final bool conserved = (m1 - m0).abs() < m0 * 0.001;

  print('flings paint outward:    $movesOut');
  print('centred blob → ring:     $fringsRing');
  print('pivot stays fixed:       $pivotFixed');
  print('finite & conservative:   ${finite && conserved}');

  if (!movesOut) throw StateError('paint did not migrate outward');
  if (!fringsRing) throw StateError('centred blob did not fling outward');
  if (!pivotFixed) throw StateError('pivot drifted (should be a fixed point)');
  if (!(finite && conserved)) throw StateError('non-finite or non-conservative');

  print('PASS');
}
