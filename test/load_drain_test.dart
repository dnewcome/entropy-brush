// Measures how far a full load lasts before drying, across mileage settings.
// Run: dart run test/load_drain_test.dart
import 'dart:math' as math;

import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';

double distanceToDry(double mileage, {double capacity = 1.6}) {
  final grid = PaintGrid(1400, 200);
  final brush =
      Brush(BrushConfig(loadCapacity: capacity, mileage: mileage));
  brush.setPigment(0.12, 0.20, 0.62);
  brush.reload();

  const dt = 1.0 / 120.0, sub = 1.5;
  double x = 60;
  const y = 100.0;
  brush.begin(StrokeSample(x, y));
  const target = 1360.0;
  while (x < target) {
    final nx = math.min(target, x + sub);
    brush.step(StrokeSample(nx, y), dt, grid);
    x = nx;
    if (brush.averageLoad < 0.05) return x - 60; // distance painted until dry
  }
  return -1; // still loaded at end of run
}

void main() {
  for (final m in [0.0, 0.3, 0.7, 1.0]) {
    final d = distanceToDry(m);
    print('mileage=${m.toStringAsFixed(1)}  '
        '${d < 0 ? "still wet after 1300px" : "dry after ${d.toStringAsFixed(0)}px"}');
  }
  print('(default is mileage 0.7, capacity 1.6)');
}
