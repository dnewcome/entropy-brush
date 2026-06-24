import 'dart:math' as math;
import 'package:entropy_brush/ui/slab_view.dart';
void main() {
  bool allOk = true;
  // Across a range of tilts / zooms / pans, projecting a canvas point and
  // inverting must recover it (so painting lands where you click).
  for (final tx in [0.0, 0.4, -0.6]) {
    for (final ty in [0.0, 0.5, -0.3]) {
      for (final zoom in [1.0, 3.0]) {
        for (final pan in [0.0, 0.4]) {
          final s = SlabView(
              viewW: 800, viewH: 800,
              tiltX: tx, tiltY: ty, zoom: zoom, panX: pan, panY: -pan,
              thickness: 0.06);
          for (final u in [0.1, 0.5, 0.83]) {
            for (final v in [0.2, 0.5, 0.77]) {
              final p = s.project(u, v, 0);
              final c = s.screenToCanvas(p.x, p.y);
              final err = math.max((c.x - u).abs(), (c.y - v).abs());
              if (err > 1e-6) {
                allOk = false;
                print('MISMATCH tx=$tx ty=$ty zoom=$zoom pan=$pan ($u,$v) -> err=$err');
              }
            }
          }
        }
      }
    }
  }
  print('projection round-trip exact across all cases: $allOk');
  // A click far off the slab maps outside 0..1.
  final s = SlabView(viewW: 800, viewH: 800);
  final off = s.screenToCanvas(10, 10);
  print('off-canvas click detected (outside 0..1): ${off.x < 0 || off.x > 1 || off.y < 0 || off.y > 1}');
}
