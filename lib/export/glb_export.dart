import 'dart:convert';
import 'dart:typed_data';

import '../sim/paint_grid.dart';

/// Build a binary glTF (.glb) relief mesh from the paint height field.
///
/// The canvas becomes a displaced grid: each sampled cell is a vertex pushed
/// out along +Z by its paint thickness, tinted by the surface pigment. This is
/// the 3D asset the downstream pipeline consumes.
Uint8List buildGlb(
  PaintGrid grid, {
  int resolution = 256,
  // Millimetres (kept consistent with the STL export). [sizeMm] is the longer
  // side; the tallest impasto reaches [reliefMm].
  double sizeMm = 100.0,
  double reliefMm = 6.0,
  // Paint thickness counts this much more than the canvas substrate, so impasto
  // stands proud of the fine canvas tooth instead of being buried in it.
  double paintWeight = 3.0,
}) {
  final int step = (grid.width > resolution || grid.height > resolution)
      ? ((grid.width > grid.height ? grid.width : grid.height) / resolution)
          .ceil()
      : 1;

  final int nx = ((grid.width - 1) ~/ step) + 1;
  final int ny = ((grid.height - 1) ~/ step) + 1;
  final int nv = nx * ny;

  final int maxDim = grid.width > grid.height ? grid.width : grid.height;
  final double worldPerCell = sizeMm / maxDim;
  final double xOff = grid.width * worldPerCell * 0.5;
  final double yOff = grid.height * worldPerCell * 0.5;

  // Weighted surface height, auto-scaled so the tallest point reaches reliefMm.
  double weightedHeight(int idx) =>
      grid.canvasHeight[idx] + grid.thickness[idx] * paintWeight;
  double hmax = 0;
  for (int i = 0; i < grid.thickness.length; i++) {
    final h = weightedHeight(i);
    if (h > hmax) hmax = h;
  }
  final double zScale = hmax > 1e-6 ? reliefMm / hmax : 0.0;

  final positions = Float32List(nv * 3);
  final colors = Float32List(nv * 4);

  double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  double maxX = -double.infinity, maxYv = -double.infinity, maxZ = -double.infinity;

  int vi = 0;
  for (int j = 0; j < ny; j++) {
    final int gy = (j * step).clamp(0, grid.height - 1);
    for (int i = 0; i < nx; i++) {
      final int gx = (i * step).clamp(0, grid.width - 1);
      final int idx = gy * grid.width + gx;

      final double x = gx * worldPerCell - xOff;
      // Negate Y so the exported mesh isn't vertically flipped (grid Y is down).
      final double y = yOff - gy * worldPerCell;
      // Substrate + paint (paint weighted up) so the bare canvas relief is in
      // the mesh too but impasto dominates.
      final double z = weightedHeight(idx) * zScale;

      positions[vi * 3] = x;
      positions[vi * 3 + 1] = y;
      positions[vi * 3 + 2] = z;
      colors[vi * 4] = grid.r[idx];
      colors[vi * 4 + 1] = grid.g[idx];
      colors[vi * 4 + 2] = grid.b[idx];
      colors[vi * 4 + 3] = 1.0;

      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxYv) maxYv = y;
      if (z > maxZ) maxZ = z;
      vi++;
    }
  }

  // Two triangles per quad.
  final int nQuads = (nx - 1) * (ny - 1);
  final indices = Uint32List(nQuads * 6);
  int ii = 0;
  for (int j = 0; j < ny - 1; j++) {
    for (int i = 0; i < nx - 1; i++) {
      final int a = j * nx + i;
      final int b = a + 1;
      final int c = a + nx;
      final int d = c + 1;
      indices[ii++] = a;
      indices[ii++] = c;
      indices[ii++] = b;
      indices[ii++] = b;
      indices[ii++] = c;
      indices[ii++] = d;
    }
  }

  // --- assemble binary buffer: positions | colors | indices ---
  final posBytes = positions.buffer.asUint8List(
      positions.offsetInBytes, positions.lengthInBytes);
  final colBytes =
      colors.buffer.asUint8List(colors.offsetInBytes, colors.lengthInBytes);
  final idxBytes = indices.buffer
      .asUint8List(indices.offsetInBytes, indices.lengthInBytes);

  final int posLen = posBytes.length;
  final int colLen = colBytes.length;
  final int idxLen = idxBytes.length;
  final int binLen = posLen + colLen + idxLen;

  final bin = Uint8List(binLen);
  bin.setRange(0, posLen, posBytes);
  bin.setRange(posLen, posLen + colLen, colBytes);
  bin.setRange(posLen + colLen, binLen, idxBytes);

  final gltf = {
    'asset': {'version': '2.0', 'generator': 'entropy-brush'},
    'scene': 0,
    'scenes': [
      {'nodes': [0]}
    ],
    'nodes': [
      {'mesh': 0}
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0, 'COLOR_0': 1},
            'indices': 2,
            'material': 0,
          }
        ]
      }
    ],
    'materials': [
      {
        'name': 'paint',
        'pbrMetallicRoughness': {
          'baseColorFactor': [1, 1, 1, 1],
          'metallicFactor': 0.0,
          'roughnessFactor': 0.85,
        }
      }
    ],
    'buffers': [
      {'byteLength': binLen}
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': posLen, 'target': 34962},
      {'buffer': 0, 'byteOffset': posLen, 'byteLength': colLen, 'target': 34962},
      {
        'buffer': 0,
        'byteOffset': posLen + colLen,
        'byteLength': idxLen,
        'target': 34963
      },
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126, // FLOAT
        'count': nv,
        'type': 'VEC3',
        'min': [minX, minY, minZ],
        'max': [maxX, maxYv, maxZ],
      },
      {
        'bufferView': 1,
        'componentType': 5126,
        'count': nv,
        'type': 'VEC4',
      },
      {
        'bufferView': 2,
        'componentType': 5125, // UNSIGNED_INT
        'count': indices.length,
        'type': 'SCALAR',
      },
    ],
  };

  return _packGlb(gltf, bin);
}

Uint8List _packGlb(Map<String, dynamic> gltf, Uint8List bin) {
  final jsonBytes = utf8.encode(json.encode(gltf));
  final int jsonPad = (4 - (jsonBytes.length % 4)) % 4;
  final int binPad = (4 - (bin.length % 4)) % 4;

  final int jsonChunkLen = jsonBytes.length + jsonPad;
  final int binChunkLen = bin.length + binPad;
  final int total = 12 + 8 + jsonChunkLen + 8 + binChunkLen;

  final out = Uint8List(total);
  final bd = ByteData.view(out.buffer);
  int o = 0;

  // Header.
  bd.setUint32(o, 0x46546C67, Endian.little); o += 4; // 'glTF'
  bd.setUint32(o, 2, Endian.little); o += 4;          // version
  bd.setUint32(o, total, Endian.little); o += 4;

  // JSON chunk.
  bd.setUint32(o, jsonChunkLen, Endian.little); o += 4;
  bd.setUint32(o, 0x4E4F534A, Endian.little); o += 4; // 'JSON'
  out.setRange(o, o + jsonBytes.length, jsonBytes); o += jsonBytes.length;
  for (int i = 0; i < jsonPad; i++) {
    out[o++] = 0x20; // space pad
  }

  // BIN chunk.
  bd.setUint32(o, binChunkLen, Endian.little); o += 4;
  bd.setUint32(o, 0x004E4942, Endian.little); o += 4; // 'BIN\0'
  out.setRange(o, o + bin.length, bin); o += bin.length;
  for (int i = 0; i < binPad; i++) {
    out[o++] = 0x00;
  }

  return out;
}
