import 'package:entropy_brush/sim/paint_grid.dart';
void main() {
  // (1) Colour follows the drip: a dark-blue blob dripping should colour its
  // trail blue, not leave canvas-cream behind the moving relief.
  final g = PaintGrid(120, 240);
  g.pile(60, 40, 6, 12.0, 0.10, 0.15, 0.70); // thick dark blue
  for (int s = 0; s < 120; s++) {
    g.flowStep(1 / 60, flow: 0, dryTime: 1000, gravX: 0, gravY: 0.3, dripYield: 0.05);
  }
  // Find the trail: painted cells in column 60 BELOW the original blob (y>48).
  int tipY = 0, n = 0; double sumB = 0, sumR = 0;
  for (int y = 49; y < g.height; y++) {
    final i = y * g.width + 60;
    if (g.thickness[i] > 0.01) { tipY = y; n++; sumB += g.b[i]; sumR += g.r[i]; }
  }
  final reached = tipY > 55;
  final blue = n > 0 && sumB / n > sumR / n + 0.2;
  print('drip trail reached y=$tipY ($n cells below blob)');
  print('trail is BLUE not cream (colour followed mass): $blue '
      '(avgR=${(sumR/n).toStringAsFixed(2)} avgB=${(sumB/n).toStringAsFixed(2)})');
  print('PASS colour-follows: ${reached && blue}');

  // (2) Thicker paint dries slower.
  double wetAfter(double amount) {
    final p = PaintGrid(80, 80);
    p.pile(40, 40, 5, amount, 0.5, 0.5, 0.5);
    for (int s = 0; s < 120; s++) {
      p.flowStep(1 / 60, flow: 0, dryTime: 1.0, gravX: 0, gravY: 0.0001);
    }
    double m = 0; for (final w in p.wet) { if (w > m) m = w; }
    return m;
  }
  print('PASS thick-dries-slower: ${wetAfter(20.0) > wetAfter(1.0) + 0.1}');
}
