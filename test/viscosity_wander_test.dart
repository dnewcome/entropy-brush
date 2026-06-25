import 'package:entropy_brush/sim/paint_grid.dart';
int footprint(PaintGrid g) { int n = 0; for (final t in g.thickness) { if (t > 0.002) n++; } return n; }

void main() {
  // Viscosity slows leveling: stiffer paint spreads less.
  int spread(double visc) {
    final g = PaintGrid(160, 160)..profile.viscosity = visc;
    g.pile(80, 80, 6, 6.0, 0.2, 0.3, 0.7);
    for (int s = 0; s < 120; s++) { g.flowStep(1/60, flow: 0.2, dryTime: 1000); }
    return footprint(g);
  }
  print('leveling footprint: runny(visc0.4)=${spread(0.4)}  stiff(visc3)=${spread(3.0)}');
  print('higher viscosity spreads less: ${spread(3.0) < spread(0.4)}');

  // Viscosity raises the effective drip yield: stiffer paint drips less far.
  double comDrop(double visc) {
    final g = PaintGrid(120, 300)..profile.viscosity = visc;
    g.pile(60, 50, 6, 10.0, 0.2, 0.3, 0.7);
    for (int s = 0; s < 120; s++) {
      g.flowStep(1/60, flow: 0.03, dryTime: 1000, gravX: 0, gravY: 0.5, dripYield: 0.06);
    }
    double t = 0, wy = 0;
    for (int i = 0; i < g.thickness.length; i++) { final th = g.thickness[i]; if (th>0){t+=th; wy+=th*(i~/g.width);} }
    return wy/t - 50;
  }
  print('drip drop: runny(visc1)=${comDrop(1.0).toStringAsFixed(1)}  stiff(visc3)=${comDrop(3.0).toStringAsFixed(1)}');
  print('higher viscosity drips less: ${comDrop(3.0) < comDrop(1.0)}');

  // Drip wander: different phase -> different drip shape.
  Set<int> dripCells(double phase) {
    final g = PaintGrid(120, 300)..dripPhase = phase;
    g.pile(60, 40, 6, 14.0, 0.2, 0.3, 0.7);
    for (int s = 0; s < 120; s++) {
      g.flowStep(1/60, flow: 0.03, dryTime: 1000, gravX: 0, gravY: 0.6, dripYield: 0.05, dripWander: 0.5);
    }
    final s = <int>{};
    for (int i = 0; i < g.thickness.length; i++) { if (g.thickness[i] > 0.01) s.add(i); }
    return s;
  }
  final a = dripCells(13.0), b = dripCells(631.0);
  final overlap = a.intersection(b).length / (a.length < b.length ? a.length : b.length);
  print('two phases -> different drip shapes (overlap ${(overlap*100).toStringAsFixed(0)}% < 90%): ${overlap < 0.9}');
}
