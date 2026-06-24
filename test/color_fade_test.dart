import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';
void main() {
  final grid = PaintGrid(800, 200);
  final brush = Brush(BrushConfig(infiniteLoad: true));
  brush.setPigment(0.12, 0.20, 0.62); // ultramarine
  brush.reload();
  double x = 40;
  brush.begin(StrokeSample(x, 100));
  while (x < 760) { x += 1.5; brush.step(StrokeSample(x, 100), 1/120, grid); }
  brush.end();
  // Sample painted surface near the END of the stroke (where fade showed up).
  double r=0,g=0,b=0; int n=0;
  for (int yy=92; yy<=108; yy++) for (int xx=700; xx<=740; xx++) {
    final i=yy*grid.width+xx;
    if (grid.thickness[i]>0.01){ r+=grid.r[i]; g+=grid.g[i]; b+=grid.b[i]; n++; }
  }
  r/=n; g/=n; b/=n;
  print('end-of-stroke colour = (${r.toStringAsFixed(2)}, ${g.toStringAsFixed(2)}, ${b.toStringAsFixed(2)})');
  print('still blue (B dominant, not browned): ${b > r + 0.1 && b > g + 0.05}');
}
