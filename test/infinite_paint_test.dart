import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';
void main() {
  for (final inf in [false, true]) {
    final grid = PaintGrid(1000, 200);
    final brush = Brush(BrushConfig(loadCapacity: 1.0, mileage: 0.3, infiniteLoad: inf));
    brush.setPigment(0.2, 0.3, 0.7);
    brush.reload();
    double x = 40;
    brush.begin(StrokeSample(x, 100));
    while (x < 960) { x += 1.5; brush.step(StrokeSample(x, 100), 1/120, grid); }
    brush.end();
    print('infinite=$inf  load after 920px = ${brush.averageLoad.toStringAsFixed(3)}');
  }
}
