import 'dart:math' as math;
import 'dart:typed_data';

import '../sim/paint_grid.dart';

/// Build a binary STL of the paint relief as a **watertight solid** suitable for
/// 3D printing or CNC: the displaced relief surface on top, a flat base, and
/// side walls joining them. (STL has no colour — geometry only.)
///
/// Real-world scaled: coordinates are in millimetres (slicers default to mm).
/// [sizeMm] is the width of the longer canvas side, [reliefMm] the height the
/// tallest impasto reaches, [baseMm] the floor thickness.
Uint8List buildStl(
  PaintGrid grid, {
  int resolution = 256,
  double sizeMm = 100.0,
  double reliefMm = 6.0,
  double baseMm = 2.0,
  double paintWeight = 3.0,
}) {
  final int step = (grid.width > resolution || grid.height > resolution)
      ? ((grid.width > grid.height ? grid.width : grid.height) / resolution)
          .ceil()
      : 1;
  final int nx = ((grid.width - 1) ~/ step) + 1;
  final int ny = ((grid.height - 1) ~/ step) + 1;

  final int maxDim = grid.width > grid.height ? grid.width : grid.height;
  final double wpc = sizeMm / maxDim;
  final double xOff = grid.width * wpc * 0.5;
  final double yOff = grid.height * wpc * 0.5;

  double weighted(int idx) =>
      grid.canvasHeight[idx] + grid.thickness[idx] * paintWeight;
  double hmax = 0;
  for (int i = 0; i < grid.thickness.length; i++) {
    final h = weighted(i);
    if (h > hmax) hmax = h;
  }
  final double zScale = hmax > 1e-6 ? reliefMm / hmax : 0.0;
  final double baseThickness = baseMm;

  final xs = Float64List(nx);
  final ys = Float64List(ny);
  for (int i = 0; i < nx; i++) {
    xs[i] = (i * step).clamp(0, grid.width - 1) * wpc - xOff;
  }
  for (int j = 0; j < ny; j++) {
    ys[j] = yOff - (j * step).clamp(0, grid.height - 1) * wpc;
  }
  final zTop = Float64List(nx * ny);
  for (int j = 0; j < ny; j++) {
    final gy = (j * step).clamp(0, grid.height - 1);
    for (int i = 0; i < nx; i++) {
      final gx = (i * step).clamp(0, grid.width - 1);
      zTop[j * nx + i] = baseThickness + weighted(gy * grid.width + gx) * zScale;
    }
  }

  final int quadsX = nx - 1, quadsY = ny - 1;
  final int triCount = quadsX * quadsY * 2 // top
      +
      quadsX * quadsY * 2 // bottom
      +
      4 * quadsX +
      4 * quadsY; // four walls

  final out = Uint8List(84 + triCount * 50);
  final bd = ByteData.view(out.buffer);
  bd.setUint32(80, triCount, Endian.little); // 80-byte header left as zeros
  int o = 84;

  double zt(int i, int j) => zTop[j * nx + i];

  // Top surface (relief), wound to face +z.
  for (int j = 0; j < quadsY; j++) {
    for (int i = 0; i < quadsX; i++) {
      o = _tri(bd, o, xs[i], ys[j], zt(i, j), xs[i], ys[j + 1], zt(i, j + 1),
          xs[i + 1], ys[j], zt(i + 1, j));
      o = _tri(bd, o, xs[i + 1], ys[j], zt(i + 1, j), xs[i], ys[j + 1],
          zt(i, j + 1), xs[i + 1], ys[j + 1], zt(i + 1, j + 1));
    }
  }
  // Flat base at z=0, wound to face -z.
  for (int j = 0; j < quadsY; j++) {
    for (int i = 0; i < quadsX; i++) {
      o = _tri(bd, o, xs[i], ys[j], 0, xs[i + 1], ys[j], 0, xs[i], ys[j + 1], 0);
      o = _tri(bd, o, xs[i + 1], ys[j], 0, xs[i + 1], ys[j + 1], 0, xs[i],
          ys[j + 1], 0);
    }
  }
  // Side walls join the top perimeter to the base — makes it watertight.
  for (int i = 0; i < quadsX; i++) {
    o = _wall(bd, o, xs[i], ys[0], zt(i, 0), xs[i + 1], ys[0], zt(i + 1, 0));
    o = _wall(bd, o, xs[i + 1], ys[ny - 1], zt(i + 1, ny - 1), xs[i],
        ys[ny - 1], zt(i, ny - 1));
  }
  for (int j = 0; j < quadsY; j++) {
    o = _wall(bd, o, xs[nx - 1], ys[j], zt(nx - 1, j), xs[nx - 1], ys[j + 1],
        zt(nx - 1, j + 1));
    o = _wall(bd, o, xs[0], ys[j + 1], zt(0, j + 1), xs[0], ys[j], zt(0, j));
  }

  return out;
}

/// Write one triangle (computes the face normal from winding).
int _tri(ByteData bd, int o, double ax, double ay, double az, double bx,
    double by, double bz, double cx, double cy, double cz) {
  double nx = (by - ay) * (cz - az) - (bz - az) * (cy - ay);
  double ny = (bz - az) * (cx - ax) - (bx - ax) * (cz - az);
  double nz = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  final double len = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (len > 1e-12) {
    nx /= len;
    ny /= len;
    nz /= len;
  }
  bd.setFloat32(o, nx, Endian.little);
  bd.setFloat32(o + 4, ny, Endian.little);
  bd.setFloat32(o + 8, nz, Endian.little);
  bd.setFloat32(o + 12, ax, Endian.little);
  bd.setFloat32(o + 16, ay, Endian.little);
  bd.setFloat32(o + 20, az, Endian.little);
  bd.setFloat32(o + 24, bx, Endian.little);
  bd.setFloat32(o + 28, by, Endian.little);
  bd.setFloat32(o + 32, bz, Endian.little);
  bd.setFloat32(o + 36, cx, Endian.little);
  bd.setFloat32(o + 40, cy, Endian.little);
  bd.setFloat32(o + 44, cz, Endian.little);
  bd.setUint16(o + 48, 0, Endian.little);
  return o + 50;
}

/// A wall quad from top edge (t1→t2) down to the base (z=0), as two triangles.
int _wall(ByteData bd, int o, double t1x, double t1y, double t1z, double t2x,
    double t2y, double t2z) {
  o = _tri(bd, o, t1x, t1y, t1z, t2x, t2y, t2z, t2x, t2y, 0);
  o = _tri(bd, o, t1x, t1y, t1z, t2x, t2y, 0, t1x, t1y, 0);
  return o;
}
