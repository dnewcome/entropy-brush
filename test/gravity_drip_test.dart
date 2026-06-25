import 'package:entropy_brush/sim/paint_grid.dart';
({double total, double comY}) stats(PaintGrid g) {
  double t = 0, wy = 0;
  for (int y = 0; y < g.height; y++) {
    for (int x = 0; x < g.width; x++) {
      final th = g.thickness[y * g.width + x];
      if (th > 0) { t += th; wy += th * y; }
    }
  }
  return (total: t, comY: t > 0 ? wy / t : 0);
}
void main() {
  // Gravity ON, pointing +y (down): a wet blob should drip downward.
  final g = PaintGrid(200, 240);
  g.pile(100, 60, 6, 6.0, 0.2, 0.3, 0.7);
  final before = stats(g);
  for (int i = 0; i < 40; i++) {
    g.flowStep(1 / 60, flow: 0, dryTime: 1000, gravX: 0, gravY: 0.12);
  }
  final after = stats(g);
  print('center-of-mass y: ${before.comY.toStringAsFixed(1)} -> ${after.comY.toStringAsFixed(1)} '
      '(drips DOWN: ${after.comY > before.comY + 3})');
  print('paint conserved: ${before.total.toStringAsFixed(2)} -> ${after.total.toStringAsFixed(2)} '
      '(${(after.total / before.total - 1).abs() < 0.02})');

  // Gravity OFF (and no leveling): nothing should move.
  final g2 = PaintGrid(200, 240);
  g2.pile(100, 60, 6, 6.0, 0.2, 0.3, 0.7);
  final b2 = stats(g2);
  for (int i = 0; i < 40; i++) {
    g2.flowStep(1 / 60, flow: 0, dryTime: 1000, gravX: 0, gravY: 0);
  }
  final a2 = stats(g2);
  print('no gravity, no flow -> static: ${(a2.comY - b2.comY).abs() < 0.01}');
}
