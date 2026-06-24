// Verifies wet-paint flow: a ridge levels out (oozes), paint is conserved while
// flowing, and the paint dries so flow stops (impasto sets).
// Run: dart run test/wet_flow_test.dart
import 'package:entropy_brush/sim/paint_grid.dart';

double total(PaintGrid g) {
  double s = 0;
  for (int i = 0; i < g.thickness.length; i++) {
    s += g.thickness[i];
  }
  return s;
}

double peak(PaintGrid g) {
  double m = 0;
  for (int i = 0; i < g.thickness.length; i++) {
    if (g.thickness[i] > m) m = g.thickness[i];
  }
  return m;
}

int footprint(PaintGrid g) {
  int n = 0;
  for (int i = 0; i < g.thickness.length; i++) {
    if (g.thickness[i] > 0.002) n++;
  }
  return n;
}

double maxWet(PaintGrid g) {
  double m = 0;
  for (int i = 0; i < g.wet.length; i++) {
    if (g.wet[i] > m) m = g.wet[i];
  }
  return m;
}

void main() {
  // A sharp mound of wet paint (don't dry during the leveling test).
  final g = PaintGrid(160, 160);
  g.pile(80, 80, 5, 6.0, 0.8, 0.2, 0.1);

  final t0 = total(g), p0 = peak(g), f0 = footprint(g);
  for (int i = 0; i < 120; i++) {
    g.flowStep(1 / 60, flow: 0.2, dryTime: 1000); // ~no drying
  }
  final t1 = total(g), p1 = peak(g), f1 = footprint(g);

  print('paint conserved while flowing: '
      '${t0.toStringAsFixed(3)} -> ${t1.toStringAsFixed(3)} '
      '(${((t1 / t0 - 1) * 100).toStringAsFixed(2)}%) '
      '-> ${(t1 / t0 - 1).abs() < 0.02}');
  print('ridge levels (peak drops): '
      '${p0.toStringAsFixed(3)} -> ${p1.toStringAsFixed(3)} -> ${p1 < p0 * 0.8}');
  print('paint oozes outward (footprint grows): $f0 -> $f1 -> ${f1 > f0}');

  // Drying: with a short dry time, flow should stop within a couple seconds.
  final g2 = PaintGrid(160, 160);
  g2.pile(80, 80, 5, 6.0, 0.3, 0.5, 0.8);
  for (int i = 0; i < 180; i++) {
    g2.flowStep(1 / 60, flow: 0.2, dryTime: 1.0); // 3s total
  }
  final wetLeft = maxWet(g2);
  final tBefore = total(g2);
  g2.flowStep(1 / 60, flow: 0.2, dryTime: 1.0);
  final tAfter = total(g2);
  print('paint dries / sets (max wet ~0): ${wetLeft.toStringAsFixed(3)} '
      '-> ${wetLeft < 0.05}');
  print('flow stops once dry (no further change): '
      '${(tAfter - tBefore).abs() < 1e-6}');
}
