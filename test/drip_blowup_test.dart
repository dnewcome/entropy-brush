import 'package:entropy_brush/sim/paint_grid.dart';
import 'package:entropy_brush/sim/paint_profile.dart';

/// Regression for the "Infinity or NaN toInt" crash in encodeHeightRGBA.
///
/// The gravity advection used to draw paint in X and Y independently, each
/// capped at 0.7·mobile, so up to 1.4·mobile could leave a single cell. The
/// clamp-at-zero on apply then turned that over-draw into *created* paint,
/// which fed back and exploded the height field to Infinity — especially with
/// a runny (low-viscosity) paint on a diagonally tilted canvas. Once any cell
/// went non-finite, encodeHeightRGBA's clamps (which don't catch NaN) crashed
/// `.round()` every frame and froze the sim.
void main() {
  final g = PaintGrid(120, 240);
  // Runny paint + diagonal gravity + wander: the worst case for the old
  // dual-draw over-draw.
  g.profile = PaintProfile(viscosity: 0.25);
  g.pile(60, 40, 7, 20.0, 0.2, 0.3, 0.7);

  double initialMass = 0;
  for (final th in g.thickness) {
    if (th > 0) initialMass += th;
  }

  for (int s = 0; s < 600; s++) {
    g.flowStep(1 / 60,
        flow: 0.03,
        dryTime: 1000,
        gravX: 0.6,
        gravY: 0.9,
        dripYield: 0.07,
        dripWander: 0.6);
  }

  // 1. Every cell must stay finite.
  bool allFinite = true;
  double finalMass = 0, peak = 0;
  for (final th in g.thickness) {
    if (!th.isFinite) allFinite = false;
    if (th > 0) finalMass += th;
    if (th > peak) peak = th;
  }

  // 2. Gravity is conservative — it moves paint, never creates it. (Drying is
  //    off, so mass should not rise above the starting amount.)
  final bool conserved = finalMass <= initialMass * 1.001;

  // 3. The encoders must not throw on the resulting field.
  bool encoded = true;
  try {
    g.encodeHeightRGBA();
    g.encodeAlbedoRGBA();
  } catch (e) {
    encoded = false;
  }

  print('initialMass=${initialMass.toStringAsFixed(2)} '
      'finalMass=${finalMass.toStringAsFixed(2)} '
      'peak=${peak.toStringAsFixed(3)}');
  print('all finite:  $allFinite');
  print('conserved:   $conserved');
  print('encoders ok: $encoded');

  if (!allFinite) throw StateError('height field went non-finite');
  if (!conserved) throw StateError('gravity created paint (non-conservative)');
  if (!encoded) throw StateError('encoders threw on the field');

  print('PASS');
}
