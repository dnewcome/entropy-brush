/// Physical properties of the paint medium itself — distinct from the brush.
///
/// These shape *what* gets laid down (how thick, how lumpy), where the brush
/// shapes *how* it's applied (bristles, load, pressure).
class PaintProfile {
  PaintProfile({
    this.body = 1.0,
    this.lumpiness = 0.25,
    this.grain = 0.12,
    this.opacity = 1.0,
  });

  /// How much paint piles per unit deposited — the "buttery vs runny" axis.
  /// Higher body builds taller impasto relief and covers more opaquely.
  double body;

  /// 0..1 strength of the canvas-locked lump/tooth texture modulating height.
  double lumpiness;

  /// Spatial frequency of the lumps (cells^-1). Small = broad clumps, large =
  /// fine grain.
  double grain;

  /// Extra coverage multiplier (how fast pigment hides what's underneath).
  double opacity;

  /// Two-octave value noise locked to canvas cell ([x],[y]) → 0..1. Locking it
  /// to position (not time) means repeated strokes deepen the *same* tooth,
  /// reading as paint texture rather than flicker.
  double grainAt(double x, double y) {
    final double f = grain;
    final double n1 = _valueNoise(x * f, y * f);
    final double n2 = _valueNoise(x * f * 2.7 + 11.3, y * f * 2.7 - 7.1);
    return (n1 * 0.65 + n2 * 0.35).clamp(0.0, 1.0);
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _hash(int x, int y) {
  int h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  h ^= h >> 16;
  return (h & 0x7fffffff) / 0x7fffffff;
}

double _valueNoise(double x, double y) {
  final int xi = x.floor();
  final int yi = y.floor();
  final double xf = x - xi;
  final double yf = y - yi;
  // Smoothstep interpolation.
  final double u = xf * xf * (3 - 2 * xf);
  final double v = yf * yf * (3 - 2 * yf);
  final double a = _hash(xi, yi);
  final double b = _hash(xi + 1, yi);
  final double c = _hash(xi, yi + 1);
  final double d = _hash(xi + 1, yi + 1);
  return _lerp(_lerp(a, b, u), _lerp(c, d, u), v);
}
