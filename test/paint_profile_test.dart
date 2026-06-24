// Pure-Dart check that paint Body scales pile height and Lumpiness adds
// surface variance. Run: dart run test/paint_profile_test.dart
import 'dart:math' as math;

import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';
import 'package:entropy_brush/sim/paint_profile.dart';

({double mean, double cov, double peak}) paintStroke(PaintProfile profile) {
  final grid = PaintGrid(400, 200);
  grid.profile = profile;
  final brush = Brush(BrushConfig(loadCapacity: 6.0));
  brush.setPigment(0.2, 0.3, 0.7);
  brush.reload();

  const dt = 1.0 / 120.0;
  double x = 40;
  const y = 100.0;
  brush.begin(StrokeSample(x, y));
  while (x < 360) {
    x += 1.5;
    brush.step(StrokeSample(x, y), dt, grid);
  }
  brush.end();

  // Sample thickness along the painted band.
  final vals = <double>[];
  for (int gx = 60; gx < 340; gx++) {
    final t = grid.thicknessAt(gx, 100);
    if (t > 0.0001) vals.add(t);
  }
  if (vals.isEmpty) return (mean: 0, cov: 0, peak: 0);
  final mean = vals.reduce((a, b) => a + b) / vals.length;
  final peak = vals.reduce(math.max);
  final variance =
      vals.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          vals.length;
  final cov = mean > 0 ? math.sqrt(variance) / mean : 0.0;
  return (mean: mean, cov: cov, peak: peak);
}

void main() {
  final thin = paintStroke(PaintProfile(body: 1.0, lumpiness: 0));
  final thick = paintStroke(PaintProfile(body: 2.0, lumpiness: 0));
  final lumpy = paintStroke(PaintProfile(body: 1.0, lumpiness: 0.9, grain: 0.15));

  print('smooth body=1  mean=${thin.mean.toStringAsFixed(4)}  cov=${thin.cov.toStringAsFixed(3)}');
  print('smooth body=2  mean=${thick.mean.toStringAsFixed(4)}  cov=${thick.cov.toStringAsFixed(3)}');
  print('lumpy  body=1  mean=${lumpy.mean.toStringAsFixed(4)}  cov=${lumpy.cov.toStringAsFixed(3)}');

  final bodyRatio = thin.peak > 0 ? thick.peak / thin.peak : 0;
  print('peak body=1 ${thin.peak.toStringAsFixed(4)}  body=2 ${thick.peak.toStringAsFixed(4)}');
  print('-> body peak ratio (expect ~2.0): ${bodyRatio.toStringAsFixed(2)}');
  print('-> lumpy adds variance (cov ${lumpy.cov.toStringAsFixed(3)} > ${thin.cov.toStringAsFixed(3)}): '
      '${lumpy.cov > thin.cov + 0.05}');
}
