import 'package:entropy_brush/sim/paint_grid.dart';
void main() {
  final g = PaintGrid(256, 256); // auto-generates texture in ctor
  double min = 1e9, max = -1e9;
  for (int i = 0; i < g.canvasHeight.length; i++) {
    if (g.canvasHeight[i] < min) min = g.canvasHeight[i];
    if (g.canvasHeight[i] > max) max = g.canvasHeight[i];
  }
  print('canvas relief range: ${min.toStringAsFixed(3)}..${max.toStringAsFixed(3)} (varies: ${max - min > 0.05})');
  final hBefore = g.heightAt(1000);
  g.clear(); // wiping paint must NOT sand the canvas
  print('substrate survives clear: ${g.heightAt(1000) == hBefore}');
  print('heightAt includes substrate: ${g.heightAt(1000) > 0}');
}
