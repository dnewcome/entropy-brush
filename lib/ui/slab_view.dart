import 'dart:math' as math;

/// A simple 2D point (no Flutter dependency, so the projection is unit-testable).
class Pt {
  const Pt(this.x, this.y);
  final double x, y;
}

/// Projects the canvas as a **3D slab** (a board with thickness) into the
/// viewport: pan moves the whole slab, zoom scales it, tilt rotates it so you
/// see its thick edges. The painting lives on the top face (the z=0 plane in
/// canvas space); the slab extends back to z = -thickness.
///
/// Because a perspective projection of a plane is a homography, mapping a screen
/// point back onto the top face (for painting) is an exact inverse-homography —
/// no ray casting needed.
class SlabView {
  SlabView({
    required this.viewW,
    required this.viewH,
    this.tiltX = 0,
    this.tiltY = 0,
    this.zoom = 1,
    this.panX = 0,
    this.panY = 0,
    this.thickness = 0.05,
    this.camDist = 3.0,
  })  : _cosX = math.cos(tiltX),
        _sinX = math.sin(tiltX),
        _cosY = math.cos(tiltY),
        _sinY = math.sin(tiltY),
        _s = 0.42 * (viewW < viewH ? viewW : viewH),
        _cx = viewW / 2,
        _cy = viewH / 2 {
    _computeHomography();
  }

  final double viewW, viewH, tiltX, tiltY, zoom, panX, panY, thickness, camDist;
  final double _cosX, _sinX, _cosY, _sinY, _s, _cx, _cy;

  /// Project a canvas point ([u],[v] in 0..1) at [depth01] (0 = top face,
  /// 1 = back face) to screen pixels.
  Pt project(double u, double v, [double depth01 = 0]) {
    final double x = u - 0.5;
    final double y = v - 0.5;
    final double z = -depth01 * thickness;
    // rotate about X (pitch), then Y (yaw)
    final double y1 = y * _cosX - z * _sinX;
    final double z1 = y * _sinX + z * _cosX;
    final double x2 = x * _cosY + z1 * _sinY;
    final double z2 = -x * _sinY + z1 * _cosY;
    final double persp = camDist / (camDist - z2);
    return Pt(
      _cx + panX * _s + x2 * persp * _s * zoom,
      _cy + panY * _s + y1 * persp * _s * zoom,
    );
  }

  // Forward homography (unit top-square → screen) and its inverse, row-major 3x3.
  late final List<double> _minv;

  void _computeHomography() {
    final p0 = project(0, 0), p1 = project(1, 0);
    final p2 = project(1, 1), p3 = project(0, 1);
    final double x0 = p0.x, y0 = p0.y, x1 = p1.x, y1 = p1.y;
    final double x2 = p2.x, y2 = p2.y, x3 = p3.x, y3 = p3.y;
    final double dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
    final double dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
    double a, b, c, d, e, f, g, h;
    if (dx3.abs() < 1e-9 && dy3.abs() < 1e-9) {
      a = x1 - x0; b = x3 - x0; c = x0;
      d = y1 - y0; e = y3 - y0; f = y0;
      g = 0; h = 0;
    } else {
      final double den = dx1 * dy2 - dx2 * dy1;
      g = (dx3 * dy2 - dx2 * dy3) / den;
      h = (dx1 * dy3 - dx3 * dy1) / den;
      a = x1 - x0 + g * x1; b = x3 - x0 + h * x3; c = x0;
      d = y1 - y0 + g * y1; e = y3 - y0 + h * y3; f = y0;
    }
    _minv = _invert3([a, b, c, d, e, f, g, h, 1]);
  }

  /// Map a screen point back to canvas ([u],[v]) on the top face. Values outside
  /// 0..1 mean the click missed the canvas.
  Pt screenToCanvas(double sx, double sy) {
    final m = _minv;
    final double wx = m[0] * sx + m[1] * sy + m[2];
    final double wy = m[3] * sx + m[4] * sy + m[5];
    final double ww = m[6] * sx + m[7] * sy + m[8];
    if (ww.abs() < 1e-12) return const Pt(-1, -1);
    return Pt(wx / ww, wy / ww);
  }
}

List<double> _invert3(List<double> m) {
  final double a = m[0], b = m[1], c = m[2];
  final double d = m[3], e = m[4], f = m[5];
  final double g = m[6], h = m[7], i = m[8];
  final double A = e * i - f * h;
  final double B = -(d * i - f * g);
  final double C = d * h - e * g;
  final double det = a * A + b * B + c * C;
  final double inv = det.abs() < 1e-12 ? 0.0 : 1.0 / det;
  return [
    A * inv, (c * h - b * i) * inv, (b * f - c * e) * inv,
    B * inv, (a * i - c * g) * inv, (c * d - a * f) * inv,
    C * inv, (b * g - a * h) * inv, (a * e - b * d) * inv,
  ];
}
