import 'package:entropy_brush/sim/paint_grid.dart';
double comY(double amount, double yield, double gravY) {
  final g = PaintGrid(160, 320);
  g.pile(80, 50, 6, amount, 0.2, 0.3, 0.7);
  for (int s = 0; s < 90; s++) {
    g.flowStep(1 / 60, flow: 0, dryTime: 1000, gravX: 0, gravY: gravY, dripYield: yield);
  }
  double t = 0, wy = 0;
  for (int i = 0; i < g.thickness.length; i++) {
    final th = g.thickness[i];
    if (th > 0) { t += th; wy += th * (i ~/ g.width); }
  }
  return t > 0 ? wy / t - 50 : 0; // downward COM shift
}
double peakOf(double amount) {
  final g = PaintGrid(160, 320);
  g.pile(80, 50, 6, amount, 0.2, 0.3, 0.7);
  double p = 0;
  for (final th in g.thickness) { if (th > p) p = th; }
  return p;
}
void main() {
  const yield = 0.08;
  print('thin  peak=${peakOf(1.5).toStringAsFixed(3)}   moved ${comY(1.5, yield, 0.3).toStringAsFixed(1)}');
  print('thick peak=${peakOf(10).toStringAsFixed(3)}    moved ${comY(10, yield, 0.3).toStringAsFixed(1)}');
  print('xthick peak=${peakOf(25).toStringAsFixed(3)}   moved ${comY(25, yield, 0.3).toStringAsFixed(1)}');
  final thin = comY(1.5, yield, 0.3), thick = comY(10, yield, 0.3), xthick = comY(25, yield, 0.3);
  print('thin holds: ${thin.abs() < 1.0}');
  print('thick drips: ${thick > 2}');
  print('more paint -> longer drip: ${xthick > thick + 3}');
}
