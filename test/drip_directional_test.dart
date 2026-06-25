import 'package:entropy_brush/sim/paint_grid.dart';
({int w, int h}) extent(double flow, double gravY, int steps) {
  final g = PaintGrid(160, 400);
  g.pile(80, 60, 6, 12.0, 0.2, 0.3, 0.7);
  for (int s = 0; s < steps; s++) {
    g.flowStep(1 / 60, flow: flow, dryTime: 1000, gravX: 0, gravY: gravY, dripYield: 0.06);
  }
  int minX = 9999, maxX = 0, minY = 9999, maxY = 0;
  for (int y = 0; y < g.height; y++) {
    for (int x = 0; x < g.width; x++) {
      if (g.thickness[y * g.width + x] > 0.01) {
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
      }
    }
  }
  return (w: maxX - minX, h: maxY - minY);
}
void main() {
  final bleed = extent(0.2, 0.15, 120);   // old: strong leveling, weak gravity
  final drip = extent(0.03, 0.65, 120);    // new: weak leveling, strong gravity
  final bleedAR = bleed.h / bleed.w;
  final dripAR = drip.h / drip.w;
  print('BLEED regime: ${bleed.w}w x ${bleed.h}h  aspect(h/w)=${bleedAR.toStringAsFixed(2)}');
  print('DRIP  regime: ${drip.w}w x ${drip.h}h  aspect(h/w)=${dripAR.toStringAsFixed(2)}');
  print('drip is much more vertical than bleed: ${dripAR > bleedAR + 1.0}');
  print('drip runs down (tall, narrow): ${drip.h > drip.w * 2}');
}
