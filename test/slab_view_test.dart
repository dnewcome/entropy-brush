import 'dart:math' as math;
import 'package:entropy_brush/ui/slab_view.dart';
void main() {
  bool allOk = true;
  for (final tx in [0.0, 0.4, -0.6]) {
    for (final ty in [0.0, 0.5, -0.3]) {
      for (final roll in [0.0, 0.7, -1.2]) {
        for (final zoom in [1.0, 3.0]) {
          for (final pan in [0.0, 0.4]) {
            final s = SlabView(
                viewW: 800, viewH: 800,
                tiltX: tx, tiltY: ty, roll: roll, zoom: zoom,
                panX: pan, panY: -pan, thickness: 0.06);
            for (final u in [0.1, 0.5, 0.83]) {
              for (final v in [0.2, 0.5, 0.77]) {
                final p = s.project(u, v, 0);
                final c = s.screenToCanvas(p.x, p.y);
                final err = math.max((c.x - u).abs(), (c.y - v).abs());
                if (err > 1e-6) { allOk = false; print('MISMATCH roll=$roll ($u,$v) err=$err'); }
              }
            }
          }
        }
      }
    }
  }
  print('projection round-trip exact (incl. roll): $allOk');
  final s = SlabView(viewW: 800, viewH: 800, roll: 0.9);
  final off = s.screenToCanvas(5, 5);
  print('off-canvas detected: ${off.x < 0 || off.x > 1 || off.y < 0 || off.y > 1}');
}
