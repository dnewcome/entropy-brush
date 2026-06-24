// Pure-Dart check that palette dabs blend so the brush can load a mixed colour.
// Run: dart run test/palette_mix_test.dart
import 'package:entropy_brush/sim/paint_grid.dart';

void main() {
  final p = PaintGrid(240, 240, maxHeight: 4.0);
  for (int i = 0; i < 8; i++) {
    p.deposit(120, 120, 7, 0.5, 0.12, 0.20, 0.62); // ultramarine
  }
  for (int i = 0; i < 8; i++) {
    p.deposit(120, 120, 7, 0.5, 0.92, 0.78, 0.12); // cadmium yellow
  }
  final rgb = <double>[0, 0, 0];
  final amt = p.sampleColor(120, 120, 12, rgb);
  print('sampled amount=${amt.toStringAsFixed(2)}  '
      'rgb=(${rgb[0].toStringAsFixed(2)}, ${rgb[1].toStringAsFixed(2)}, ${rgb[2].toStringAsFixed(2)})');
  // Subtractive blue + yellow should read green: G the dominant channel.
  final green = rgb[1] >= rgb[0] && rgb[1] >= rgb[2];
  print('green-ish (G dominant, subtractive mix): $green');
}
