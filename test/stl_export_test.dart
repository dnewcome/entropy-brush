// Verifies the STL is a valid binary STL and a watertight solid (every edge is
// shared by exactly two triangles). Run: dart run test/stl_export_test.dart
import 'dart:typed_data';

import 'package:entropy_brush/export/stl_export.dart';
import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';

void main() {
  final grid = PaintGrid(128, 128);
  final brush = Brush(BrushConfig(loadCapacity: 4, mileage: 1.0));
  brush.setPigment(0.8, 0.1, 0.1);
  brush.reload();
  double x = 20;
  brush.begin(StrokeSample(x, 64));
  while (x < 108) {
    x += 1.5;
    brush.step(StrokeSample(x, 64), 1 / 120, grid);
  }
  brush.end();

  final stl = buildStl(grid);
  final bd = ByteData.sublistView(stl);

  // Binary STL must not start with "solid".
  final header = String.fromCharCodes(stl.sublist(0, 5));
  final triCount = bd.getUint32(80, Endian.little);
  final sizeOk = stl.length == 84 + triCount * 50;
  print('binary STL (header != "solid"): ${header != "solid"}');
  print('triangles=$triCount  size matches header: $sizeOk');

  // Watertight: build undirected edge multiset; each must be used exactly twice.
  String vkey(double a, double b, double c) =>
      '${a.toStringAsFixed(5)},${b.toStringAsFixed(5)},${c.toStringAsFixed(5)}';
  final edges = <String, int>{};
  int o = 84;
  for (int t = 0; t < triCount; t++) {
    final vs = <String>[];
    for (int v = 0; v < 3; v++) {
      final base = o + 12 + v * 12;
      vs.add(vkey(bd.getFloat32(base, Endian.little),
          bd.getFloat32(base + 4, Endian.little),
          bd.getFloat32(base + 8, Endian.little)));
    }
    for (int e = 0; e < 3; e++) {
      final a = vs[e], b = vs[(e + 1) % 3];
      final key = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
      edges[key] = (edges[key] ?? 0) + 1;
    }
    o += 50;
  }
  int bad = 0;
  for (final n in edges.values) {
    if (n != 2) bad++;
  }
  print('unique edges=${edges.length}  non-manifold edges=$bad');
  print('watertight (every edge shared by exactly 2 tris): ${bad == 0}');
}
