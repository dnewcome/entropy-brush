// Pure-Dart check that a held "squirt" grows a blob over frames (mirrors
// PaintController._squirt). Run: dart run test/squirt_test.dart
import 'dart:math' as math;

import 'package:entropy_brush/sim/paint_grid.dart';

void main() {
  final p = PaintGrid(240, 240, maxHeight: 4.0);
  const cx = 120.0, cy = 120.0;
  const volPerFrame = 1.2;
  const maxRadius = 16.0;
  double accum = 0;

  int paintedRadius() {
    int rmax = 0;
    for (int dx = 0; dx < 100; dx++) {
      if (p.thicknessAt(120 + dx, 120) > 0.001) rmax = dx;
    }
    return rmax;
  }

  for (int frame = 1; frame <= 40; frame++) {
    accum += volPerFrame;
    final radius = math.min(maxRadius, 6.0 + math.sqrt(accum) * 1.8);
    p.deposit(cx, cy, radius, volPerFrame, 0.78, 0.12, 0.10); // cadmium red
    if (frame % 10 == 0) {
      print('frame=$frame  centerHeight=${p.thicknessAt(120, 120).toStringAsFixed(2)}  '
          'footprintRadius=${paintedRadius()}px');
    }
  }
}
