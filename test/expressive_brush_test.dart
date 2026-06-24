// Verifies expressive brushwork:
//  A. the drybrush tooth-gate (low coverage -> paint only on canvas peaks);
//  B. the brush's reach (coverage) falls as the load runs out.
// Run: dart run test/expressive_brush_test.dart
import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';

void main() {
  // --- A. tooth-gate in isolation ---
  final g = PaintGrid(200, 200); // canvas tooth amplitude 0.08
  // One broad scumble dab (coverage 0.35 => only peaks should catch paint).
  g.deposit(100, 100, 30, 6.0, 0.8, 0.1, 0.1, coverage: 0.35);

  int nPaint = 0, nBare = 0;
  double hPaint = 0, hBare = 0;
  for (int y = 75; y <= 125; y++) {
    for (int x = 75; x <= 125; x++) {
      final i = y * g.width + x;
      if (g.thickness[i] > 0.0015) {
        nPaint++;
        hPaint += g.canvasHeight[i];
      } else {
        nBare++;
        hBare += g.canvasHeight[i];
      }
    }
  }
  final cover = nPaint / (nPaint + nBare);
  final mp = hPaint / nPaint, mb = hBare / nBare;
  print('scumble coverage=${(cover * 100).toStringAsFixed(0)}% '
      '(partial, not solid: ${cover > 0.1 && cover < 0.9})');
  print('paint caught on PEAKS: painted tooth=${mp.toStringAsFixed(4)} > '
      'bare tooth=${mb.toStringAsFixed(4)} -> ${mp > mb}');

  // --- B. brush reach falls as it dries ---
  final grid = PaintGrid(640, 200);
  final brush = Brush(BrushConfig(loadCapacity: 1.0, mileage: 0.3));
  brush.setPigment(0.12, 0.20, 0.62);
  brush.reload();
  const dt = 1.0 / 120.0;
  double coverWet = -1, coverMid = -1;
  double x = 40;
  brush.begin(StrokeSample(x, 100));
  while (x < 360) {
    x += 1.5;
    brush.step(StrokeSample(x, 100), dt, grid);
  }
  brush.end();
  // Coverage in a band, early vs later.
  double bandCover(int xa, int xb) {
    int hit = 0, tot = 0;
    for (int yy = 88; yy <= 112; yy++) {
      for (int xx = xa; xx <= xb; xx++) {
        tot++;
        if (grid.thickness[yy * grid.width + xx] > 0.0015) hit++;
      }
    }
    return hit / tot;
  }

  coverWet = bandCover(60, 120);
  coverMid = bandCover(200, 260);
  print('brush coverage wet=${(coverWet * 100).toStringAsFixed(0)}% '
      '-> drying=${(coverMid * 100).toStringAsFixed(0)}% '
      '(breaks up: ${coverMid < coverWet})');
}
