// Verifies the GLB mesh is displaced AND that painted impasto rises above the
// bare canvas. Parses vertex positions out of the BIN chunk.
// Run: dart run test/glb_export_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:entropy_brush/export/glb_export.dart';
import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';

void main() {
  const n = 256;
  final grid = PaintGrid(n, n); // canvas tooth from ctor (subtle now)
  final brush = Brush(BrushConfig(loadCapacity: 4, mileage: 1.0));
  brush.setPigment(0.8, 0.1, 0.1);
  brush.reload();
  const dt = 1.0 / 120.0;
  double x = 40;
  brush.begin(StrokeSample(x, 128));
  while (x < 220) {
    x += 1.5;
    brush.step(StrokeSample(x, 128), dt, grid);
  }
  brush.end();

  final glb = buildGlb(grid); // step=1 at 256, so vertex grid == cell grid
  final bd = ByteData.sublistView(glb);
  final magic = bd.getUint32(0, Endian.little) == 0x46546C67;
  final jsonLen = bd.getUint32(12, Endian.little);
  final gltf = json.decode(utf8.decode(glb.sublist(20, 20 + jsonLen)))
      as Map<String, dynamic>;
  final posAcc = (gltf['accessors'] as List)[0] as Map<String, dynamic>;
  final count = posAcc['count'] as int;

  // BIN chunk: after header(12) + json chunk header(8) + jsonLen + bin header(8).
  final binStart = 20 + jsonLen + 8;
  final pos = Float32List.sublistView(
      Uint8List.sublistView(glb, binStart, binStart + count * 12));

  double zAt(int gx, int gy) => pos[(gy * n + gx) * 3 + 2];

  // Peak of the stroke band (striations mean individual cells may be bare).
  double zPaintPeak = 0;
  for (int gy = 118; gy <= 138; gy++) {
    for (int gx = 50; gx <= 210; gx++) {
      if (zAt(gx, gy) > zPaintPeak) zPaintPeak = zAt(gx, gy);
    }
  }
  final zBare1 = zAt(10, 10); // far corner, unpainted
  final zBare2 = zAt(240, 20); // another unpainted spot

  print('GLB valid: $magic  vertices=$count');
  print('stroke-band peak z = ${zPaintPeak.toStringAsFixed(4)}');
  print('z bare canvas = ${zBare1.toStringAsFixed(4)}, ${zBare2.toStringAsFixed(4)}');
  print('mesh displaced (not flat): ${zPaintPeak.abs() > 0.02}');
  print('impasto stands above bare canvas: '
      '${zPaintPeak > zBare1 + 0.03 && zPaintPeak > zBare2 + 0.03}');
}
