import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';
double strokeTotal(double dwell) {
  final grid = PaintGrid(400, 200);
  final brush = Brush(BrushConfig(loadCapacity: 8, mileage: 1.0));
  brush.setPigment(0.2, 0.3, 0.7);
  brush.reload();
  double x = 40;
  brush.begin(StrokeSample(x, 100));
  while (x < 360) { x += 1.5; brush.dwell = dwell; brush.step(StrokeSample(x, 100), 1/120, grid); }
  brush.end();
  double t = 0; for (final th in grid.thickness) { t += th; }
  return t;
}
void main() {
  final fast = strokeTotal(0.0);
  final slow = strokeTotal(1.0);
  print('fast-stroke paint=${fast.toStringAsFixed(2)}  slow-stroke paint=${slow.toStringAsFixed(2)}');
  print('slow strokes pool more paint: ${slow > fast * 1.5}');

  // Terminal pool on lift.
  final grid = PaintGrid(200, 200);
  final brush = Brush(BrushConfig(loadCapacity: 4));
  brush.setPigment(0.8, 0.1, 0.1);
  brush.reload();
  brush.begin(StrokeSample(100, 100));
  brush.dwell = 1.0;
  final loadBefore = brush.averageLoad;
  brush.layPool(grid);
  double poolMax = 0;
  for (int y = 90; y <= 110; y++) {
    for (int x = 90; x <= 110; x++) { final v = grid.thicknessAt(x, y); if (v > poolMax) poolMax = v; }
  }
  print('terminal pool deposited at lift: ${poolMax > 0.01}');
  print('pool drawn from load (depleted): ${brush.averageLoad < loadBefore}');
}
