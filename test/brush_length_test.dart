// Verifies the brush-length model: scrape/pile conserve paint, and pressure
// flattens the brush so the contact footprint reaches further forward.
// Run: dart run test/brush_length_test.dart
import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';

double totalThickness(PaintGrid g) {
  double s = 0;
  for (int i = 0; i < g.thickness.length; i++) {
    s += g.thickness[i];
  }
  return s;
}

double leadingExtent(double pressure) {
  final grid = PaintGrid(400, 400);
  // Isolate the footprint: no plowing.
  final brush = Brush(BrushConfig(displacement: 0, bristleLength: 14));
  brush.setPigment(0.2, 0.3, 0.7);
  brush.reload();
  // One short move to the right at the given pressure.
  brush.begin(StrokeSample(200, 200, pressure: pressure));
  for (int k = 1; k <= 4; k++) {
    brush.step(StrokeSample(200.0 + k * 2, 200, pressure: pressure), 1 / 120, grid);
  }
  brush.end();
  // Furthest-forward painted column.
  double maxX = 0;
  for (int y = 0; y < grid.height; y++) {
    for (int x = grid.width - 1; x >= 0; x--) {
      if (grid.thickness[y * grid.width + x] > 0.002) {
        if (x > maxX) maxX = x.toDouble();
        break;
      }
    }
  }
  return maxX;
}

void main() {
  // --- pile conserves the amount added ---
  final g = PaintGrid(120, 120);
  final before = totalThickness(g);
  g.pile(60, 60, 10, 4.0, 0.5, 0.4, 0.3);
  final piled = totalThickness(g) - before;
  print('pile conserves: added=${piled.toStringAsFixed(3)} (~4.0): '
      '${(piled - 4.0).abs() < 0.05}');

  // --- scrape removes what it returns ---
  final rgb = <double>[0, 0, 0];
  final t0 = totalThickness(g);
  final removed = g.scrape(60, 60, 10, 0.5, rgb);
  final t1 = totalThickness(g);
  print('scrape conserves: returned=${removed.toStringAsFixed(3)} '
      'removed=${(t0 - t1).toStringAsFixed(3)}: '
      '${(removed - (t0 - t1)).abs() < 1e-6 && removed > 0}');

  // --- pressure lengthens the contact footprint ---
  final low = leadingExtent(0.15);
  final high = leadingExtent(1.0);
  print('leading extent: press0.15=${low.toStringAsFixed(0)}  '
      'press1.0=${high.toStringAsFixed(0)}  '
      '-> flattens forward with pressure: ${high > low + 2}');

  // --- displacement conserves paint (plows, not destroys) ---
  double strokeTotal(double disp) {
    final grid = PaintGrid(600, 200);
    final brush = Brush(BrushConfig(displacement: disp, loadCapacity: 3));
    brush.setPigment(0.8, 0.2, 0.1);
    brush.reload();
    double x = 60;
    brush.begin(StrokeSample(x, 100));
    while (x < 400) {
      x += 1.5;
      brush.step(StrokeSample(x, 100), 1 / 120, grid);
    }
    brush.end();
    return totalThickness(grid);
  }

  final noDisp = strokeTotal(0.0);
  final withDisp = strokeTotal(0.6);
  final ratio = withDisp / noDisp;
  print('displacement conserves paint (ratio ~1): ${ratio.toStringAsFixed(3)} '
      '-> ${(ratio - 1.0).abs() < 0.1}');
}
