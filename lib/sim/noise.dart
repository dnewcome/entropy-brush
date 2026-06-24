// Small, fast value-noise (Perlin-style) helpers shared by the canvas-texture
// generator and the paint lumpiness field.

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _hash(int x, int y) {
  int h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  h ^= h >> 16;
  return (h & 0x7fffffff) / 0x7fffffff;
}

/// Smooth value noise at ([x],[y]) → 0..1.
double valueNoise(double x, double y) {
  final int xi = x.floor();
  final int yi = y.floor();
  final double xf = x - xi;
  final double yf = y - yi;
  final double u = xf * xf * (3 - 2 * xf);
  final double v = yf * yf * (3 - 2 * yf);
  final double a = _hash(xi, yi);
  final double b = _hash(xi + 1, yi);
  final double c = _hash(xi, yi + 1);
  final double d = _hash(xi + 1, yi + 1);
  return _lerp(_lerp(a, b, u), _lerp(c, d, u), v);
}

/// Fractal (multi-octave) value noise → 0..1.
double fbm(double x, double y,
    {int octaves = 4, double lacunarity = 2.0, double gain = 0.5}) {
  double sum = 0, amp = 0.5, freq = 1, norm = 0;
  for (int i = 0; i < octaves; i++) {
    sum += amp * valueNoise(x * freq, y * freq);
    norm += amp;
    amp *= gain;
    freq *= lacunarity;
  }
  return norm > 0 ? sum / norm : 0;
}
