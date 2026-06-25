import 'dart:math' as math;
import 'dart:typed_data';

import 'noise.dart';
import 'paint_profile.dart';

/// The canvas as a height field of paint.
///
/// Every cell stores the paint *thickness* (relief) and the colour of the
/// top surface. Bristles deposit into and lift from these cells; the relief
/// shader later turns [heightAt] into normals for lighting and the mesh
/// exporter turns it into geometry.
class PaintGrid {
  PaintGrid(this.width, this.height, {this.maxHeight = 8.0})
      : thickness = Float32List(width * height),
        canvasHeight = Float32List(width * height),
        wet = Float32List(width * height),
        r = Float32List(width * height),
        g = Float32List(width * height),
        b = Float32List(width * height) {
    clear();
    generateCanvasTexture();
  }

  final int width;
  final int height;

  /// Thickness used to normalise the packed height texture. Paint taller than
  /// this clamps in the relief render (but is preserved for mesh export).
  final double maxHeight;

  /// Paint thickness per cell, in arbitrary units (~mm).
  final Float32List thickness;

  /// Base canvas substrate relief (linen tooth / weave) in the same units. The
  /// relief render and mesh export use thickness + canvasHeight, so even bare
  /// canvas is 3D. Survives [clear] — wiping paint doesn't sand the canvas.
  final Float32List canvasHeight;

  /// Wetness per cell (0..1). Fresh paint is wet and flows/levels; it dries over
  /// time and sets, locking in the impasto. Only wet paint participates in flow.
  final Float32List wet;

  // Bounding box of currently-wet paint, so flow only touches the live region.
  int _wetMinX = 0, _wetMinY = 0, _wetMaxX = 0, _wetMaxY = 0;
  bool _hasWet = false;

  // Scratch buffers for the flow step (allocated lazily, reused each frame).
  Float32List? _dH, _inA, _inR, _inG, _inB;

  void _wetTouch(int x, int y) {
    wet[y * width + x] = 1.0;
    if (!_hasWet) {
      _wetMinX = x;
      _wetMinY = y;
      _wetMaxX = x;
      _wetMaxY = y;
      _hasWet = true;
      return;
    }
    if (x < _wetMinX) _wetMinX = x;
    if (y < _wetMinY) _wetMinY = y;
    if (x > _wetMaxX) _wetMaxX = x;
    if (y > _wetMaxY) _wetMaxY = y;
  }

  /// Combined surface height (substrate + paint) used for lighting and export.
  double heightAt(int i) => canvasHeight[i] + thickness[i];

  /// (Re)build the canvas substrate as fractal (Perlin-style) noise. [amplitude]
  /// is the tooth depth in thickness units, [scale] the spatial frequency.
  /// Amplitude of the current canvas tooth, used to normalise it for the
  /// drybrush/scumble gating in [deposit]. 0 means a smooth (e.g. palette) grid.
  double canvasToothAmplitude = 0.08;

  void generateCanvasTexture(
      {double amplitude = 0.08, double scale = 0.16, int seed = 1}) {
    canvasToothAmplitude = amplitude;
    final double off = seed * 53.13;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final double n =
            fbm(x * scale + off, y * scale + off, octaves: 3);
        canvasHeight[y * width + x] = n * amplitude;
      }
    }
    _dirtyAll();
  }

  /// Top-surface pigment colour, linear 0..1.
  final Float32List r, g, b;

  /// Active paint medium — controls how thick and lumpy deposits are.
  PaintProfile profile = PaintProfile();

  // Bare canvas colour shown where no paint has been laid.
  static const double canvasR = 0.92;
  static const double canvasG = 0.89;
  static const double canvasB = 0.82;

  // Dirty rectangle so the renderer only re-encodes what changed.
  int _dirtyMinX = 0, _dirtyMinY = 0, _dirtyMaxX = 0, _dirtyMaxY = 0;
  bool _dirty = false;

  bool get isDirty => _dirty;

  void clear() {
    for (int i = 0; i < thickness.length; i++) {
      thickness[i] = 0;
      wet[i] = 0;
      r[i] = canvasR;
      g[i] = canvasG;
      b[i] = canvasB;
    }
    _hasWet = false;
    _dirtyAll();
  }

  void _dirtyAll() {
    _dirty = true;
    _dirtyMinX = 0;
    _dirtyMinY = 0;
    _dirtyMaxX = width;
    _dirtyMaxY = height;
  }

  void resetDirty() => _dirty = false;

  void _touch(int x, int y) {
    if (!_dirty) {
      _dirtyMinX = x;
      _dirtyMinY = y;
      _dirtyMaxX = x + 1;
      _dirtyMaxY = y + 1;
      _dirty = true;
      return;
    }
    if (x < _dirtyMinX) _dirtyMinX = x;
    if (y < _dirtyMinY) _dirtyMinY = y;
    if (x + 1 > _dirtyMaxX) _dirtyMaxX = x + 1;
    if (y + 1 > _dirtyMaxY) _dirtyMaxY = y + 1;
  }

  double thicknessAt(int x, int y) => thickness[y * width + x];

  /// Deposit [volume] of pigment ([pr],[pg],[pb]) as a soft round dab centred
  /// at ([cx],[cy]) with radius [radius] (cells). Returns the volume actually
  /// laid down (always == volume here; gating happens in the brush).
  ///
  /// Colour mixes wet-on-wet: a dab tints the existing surface in proportion
  /// to how much it covers, so overlapping strokes blend instead of replace.
  ///
  /// [coverage] (0..1) is how deeply the brush reaches into the canvas tooth: 1
  /// floods the valleys (smooth, loaded paint); lower values let only the raised
  /// tooth peaks catch paint, producing drybrush / scumble that reveals the
  /// canvas weave.
  void deposit(double cx, double cy, double radius, double volume, double pr,
      double pg, double pb, {double coverage = 1.0}) {
    if (volume <= 0) return;
    final bool gateTooth = coverage < 0.999 && canvasToothAmplitude > 1e-6;
    final double toothThresh = 1.0 - coverage;
    final double invToothAmp =
        canvasToothAmplitude > 0 ? 1.0 / canvasToothAmplitude : 0.0;
    final int x0 = math.max(0, (cx - radius).floor());
    final int x1 = math.min(width - 1, (cx + radius).ceil());
    final int y0 = math.max(0, (cy - radius).floor());
    final int y1 = math.min(height - 1, (cy + radius).ceil());
    if (x0 > x1 || y0 > y1) return;

    final double invR2 = 1.0 / (radius * radius);
    // Normalise the gaussian-ish weights so total deposited ~= volume.
    double wsum = 0;
    for (int y = y0; y <= y1; y++) {
      final double dy = y - cy;
      for (int x = x0; x <= x1; x++) {
        final double dx = x - cx;
        final double t = (dx * dx + dy * dy) * invR2;
        if (t <= 1.0) wsum += (1.0 - t) * (1.0 - t);
      }
    }
    if (wsum <= 0) return;
    final double k = volume / wsum;

    for (int y = y0; y <= y1; y++) {
      final double dy = y - cy;
      for (int x = x0; x <= x1; x++) {
        final double dx = x - cx;
        final double t = (dx * dx + dy * dy) * invR2;
        if (t > 1.0) continue;
        final double w = (1.0 - t) * (1.0 - t);
        final int i = y * width + x;

        // Body sets how much the paint piles; lumpiness modulates it with a
        // canvas-locked noise field so the relief breaks into ridges/clumps.
        double lumpMul = 1.0;
        if (profile.lumpiness > 0) {
          final double n = profile.grainAt(x.toDouble(), y.toDouble());
          lumpMul = 1.0 + profile.lumpiness * (n - 0.5) * 1.8;
          if (lumpMul < 0) lumpMul = 0;
        }

        // Drybrush gate: high tooth (peaks) catch paint first; valleys only as
        // coverage approaches 1.
        double toothGate = 1.0;
        if (gateTooth) {
          final double toothN = (canvasHeight[i] * invToothAmp).clamp(0.0, 1.0);
          toothGate =
              _smoothstep(toothThresh - 0.18, toothThresh + 0.06, toothN);
          if (toothGate <= 0) continue;
        }

        final double add = w * k * profile.body * lumpMul * toothGate;
        thickness[i] += add;
        _wetTouch(x, y);

        // Coverage drives how strongly the new pigment tints the surface.
        // Mixing is subtractive (Kubelka-Munk per channel) so pigments blend
        // like paint — blue + yellow makes green, not muddy grey.
        final double cover = (add * 6.0 * profile.opacity).clamp(0.0, 1.0);
        r[i] = _kmMix(r[i], pr, cover);
        g[i] = _kmMix(g[i], pg, cover);
        b[i] = _kmMix(b[i], pb, cover);
        _touch(x, y);
      }
    }
  }

  /// Read-only sample of the wet paint under ([cx],[cy]): the thickness-weighted
  /// average surface colour goes into [outRgb], and the total thickness present
  /// is returned. Used for wet-on-wet colour pickup — it does NOT remove paint,
  /// so strokes blend without destroying material and the brush load only ever
  /// drains.
  double sampleColor(double cx, double cy, double radius, List<double> outRgb) {
    final int x0 = math.max(0, (cx - radius).floor());
    final int x1 = math.min(width - 1, (cx + radius).ceil());
    final int y0 = math.max(0, (cy - radius).floor());
    final int y1 = math.min(height - 1, (cy + radius).ceil());
    if (x0 > x1 || y0 > y1) return 0;

    double wr = 0, wg = 0, wb = 0, wsum = 0, total = 0;
    final double invR2 = 1.0 / (radius * radius);
    for (int y = y0; y <= y1; y++) {
      final double dy = y - cy;
      for (int x = x0; x <= x1; x++) {
        final double dx = x - cx;
        final double t = (dx * dx + dy * dy) * invR2;
        if (t > 1.0) continue;
        final int i = y * width + x;
        final double th = thickness[i];
        if (th <= 0) continue;
        final double w = (1.0 - t) * th; // weight by how much paint is there
        wr += r[i] * w;
        wg += g[i] * w;
        wb += b[i] * w;
        wsum += w;
        total += th;
      }
    }
    if (wsum > 0) {
      outRgb[0] = wr / wsum;
      outRgb[1] = wg / wsum;
      outRgb[2] = wb / wsum;
    }
    return total;
  }

  /// Remove [fraction] of the paint thickness in a dab at ([cx],[cy]) and return
  /// the total amount removed, with its thickness-weighted colour in [outRgb].
  /// Pair with [pile] to push paint around (a bristle plowing wet paint).
  double scrape(double cx, double cy, double radius, double fraction,
      List<double> outRgb) {
    final int x0 = math.max(0, (cx - radius).floor());
    final int x1 = math.min(width - 1, (cx + radius).ceil());
    final int y0 = math.max(0, (cy - radius).floor());
    final int y1 = math.min(height - 1, (cy + radius).ceil());
    if (x0 > x1 || y0 > y1) return 0;

    double wr = 0, wg = 0, wb = 0, removed = 0;
    final double invR2 = 1.0 / (radius * radius);
    for (int y = y0; y <= y1; y++) {
      final double dy = y - cy;
      for (int x = x0; x <= x1; x++) {
        final double dx = x - cx;
        final double t = (dx * dx + dy * dy) * invR2;
        if (t > 1.0) continue;
        final int i = y * width + x;
        final double th = thickness[i];
        if (th <= 0) continue;
        final double take = th * fraction * (1.0 - t);
        thickness[i] = th - take;
        wr += r[i] * take;
        wg += g[i] * take;
        wb += b[i] * take;
        removed += take;
        _touch(x, y);
      }
    }
    if (removed > 0) {
      outRgb[0] = wr / removed;
      outRgb[1] = wg / removed;
      outRgb[2] = wb / removed;
    }
    return removed;
  }

  /// Conservatively add [amount] of thickness (and colour) as a soft dab —
  /// like [deposit] but with no body/lumpiness/tooth modulation, so paint moved
  /// by [scrape] is preserved exactly. Used for paint displacement / ridging.
  void pile(double cx, double cy, double radius, double amount, double pr,
      double pg, double pb) {
    if (amount <= 0) return;
    final int x0 = math.max(0, (cx - radius).floor());
    final int x1 = math.min(width - 1, (cx + radius).ceil());
    final int y0 = math.max(0, (cy - radius).floor());
    final int y1 = math.min(height - 1, (cy + radius).ceil());
    if (x0 > x1 || y0 > y1) return;

    final double invR2 = 1.0 / (radius * radius);
    double wsum = 0;
    for (int y = y0; y <= y1; y++) {
      final double dy = y - cy;
      for (int x = x0; x <= x1; x++) {
        final double dx = x - cx;
        final double t = (dx * dx + dy * dy) * invR2;
        if (t <= 1.0) wsum += (1.0 - t) * (1.0 - t);
      }
    }
    if (wsum <= 0) return;
    final double k = amount / wsum;
    for (int y = y0; y <= y1; y++) {
      final double dy = y - cy;
      for (int x = x0; x <= x1; x++) {
        final double dx = x - cx;
        final double t = (dx * dx + dy * dy) * invR2;
        if (t > 1.0) continue;
        final int i = y * width + x;
        final double add = (1.0 - t) * (1.0 - t) * k;
        thickness[i] += add;
        _wetTouch(x, y);
        final double cover = (add * 6.0).clamp(0.0, 1.0);
        r[i] = _kmMix(r[i], pr, cover);
        g[i] = _kmMix(g[i], pg, cover);
        b[i] = _kmMix(b[i], pb, cover);
        _touch(x, y);
      }
    }
  }

  /// One step of wet-paint flow: wet paint levels downhill (surface tension /
  /// gravity), oozing into neighbours and bleeding colour wet-on-wet, then dries
  /// a little so impasto eventually sets. Conservative — paint is moved, not
  /// created. [flow] is the leveling rate, [dryTime] seconds to mostly dry.
  /// [gravX]/[gravY] are the in-plane gravity vector (cells of drift per step);
  /// non-zero makes wet paint run downhill (drips), on top of the leveling.
  void flowStep(double dt,
      {double flow = 0.2,
      double dryTime = 3.0,
      double gravX = 0,
      double gravY = 0}) {
    final bool grav = gravX != 0 || gravY != 0;
    if (!_hasWet || (flow <= 0 && !grav)) return;
    final int x0 = math.max(1, _wetMinX);
    final int y0 = math.max(1, _wetMinY);
    final int x1 = math.min(width - 2, _wetMaxX);
    final int y1 = math.min(height - 2, _wetMaxY);
    if (x0 > x1 || y0 > y1) {
      _hasWet = false;
      return;
    }

    final dH = _dH ??= Float32List(width * height);
    final inA = _inA ??= Float32List(width * height);
    final inR = _inR ??= Float32List(width * height);
    final inG = _inG ??= Float32List(width * height);
    final inB = _inB ??= Float32List(width * height);

    // Zero scratch over the bbox plus a 1-cell margin (flow writes to neighbours).
    for (int y = y0 - 1; y <= y1 + 1; y++) {
      final int base = y * width;
      for (int x = x0 - 1; x <= x1 + 1; x++) {
        final int i = base + x;
        dH[i] = 0;
        inA[i] = 0;
        inR[i] = 0;
        inG[i] = 0;
        inB[i] = 0;
      }
    }

    final double k = flow.clamp(0.0, 0.2);
    for (int y = y0; y <= y1; y++) {
      final int base = y * width;
      for (int x = x0; x <= x1; x++) {
        final int i = base + x;
        if (wet[i] <= 0.002) continue;
        final double hi = thickness[i];
        // +x and +y neighbours (each cell pair handled once). The uphill cell
        // pushes paint downhill, gated by its own wetness.
        for (int n = 0; n < 2; n++) {
          final int j = n == 0 ? i + 1 : i + width;
          final double hj = thickness[j];
          final double diff = hi - hj;
          if (diff == 0) continue;
          final double gate = diff > 0 ? wet[i] : wet[j];
          if (gate <= 0.002) continue;
          final double f = k * gate * diff;
          dH[i] -= f;
          dH[j] += f;
          // Paint carries its colour to the cell it flows into.
          final double amt = f.abs();
          if (f > 0) {
            inA[j] += amt;
            inR[j] += amt * r[i];
            inG[j] += amt * g[i];
            inB[j] += amt * b[i];
          } else {
            inA[i] += amt;
            inR[i] += amt * r[j];
            inG[i] += amt * g[j];
            inB[i] += amt * b[j];
          }
        }

        // Gravity: wet paint slides downhill in the (gravX, gravY) direction,
        // conservatively into the downstream neighbour — this makes drips.
        if (grav) {
          final double th = thickness[i];
          final double wi = wet[i];
          if (gravX != 0) {
            final int j = gravX > 0 ? i + 1 : i - 1;
            double amt = gravX.abs() * th * wi;
            if (amt > th * 0.5) amt = th * 0.5;
            if (amt > 0) {
              dH[i] -= amt;
              dH[j] += amt;
              inA[j] += amt;
              inR[j] += amt * r[i];
              inG[j] += amt * g[i];
              inB[j] += amt * b[i];
            }
          }
          if (gravY != 0) {
            final int j = gravY > 0 ? i + width : i - width;
            double amt = gravY.abs() * th * wi;
            if (amt > th * 0.5) amt = th * 0.5;
            if (amt > 0) {
              dH[i] -= amt;
              dH[j] += amt;
              inA[j] += amt;
              inR[j] += amt * r[i];
              inG[j] += amt * g[i];
              inB[j] += amt * b[i];
            }
          }
        }
      }
    }

    // Apply height/colour deltas and dry, tracking the shrinking wet region.
    final double dryF = math.exp(-dt / math.max(0.05, dryTime));
    double maxWet = 0;
    int nMinX = width, nMinY = height, nMaxX = 0, nMaxY = 0;
    for (int y = y0 - 1; y <= y1 + 1; y++) {
      final int base = y * width;
      for (int x = x0 - 1; x <= x1 + 1; x++) {
        final int i = base + x;
        final double d = dH[i];
        if (d != 0) {
          double nt = thickness[i] + d;
          if (nt < 0) nt = 0;
          thickness[i] = nt;
          final double ia = inA[i];
          if (ia > 0) {
            final double frac = (ia / (nt + 1e-6)).clamp(0.0, 1.0) * 0.6;
            r[i] = _kmMix(r[i], inR[i] / ia, frac);
            g[i] = _kmMix(g[i], inG[i] / ia, frac);
            b[i] = _kmMix(b[i], inB[i] / ia, frac);
          }
          _touch(x, y);
        }
        double w = wet[i];
        // Cells the drip ran into stay wet so it keeps running — drying still
        // bounds how far a drip travels before it sets.
        if (grav && inA[i] > 0.0008 && w < 0.5) w = 0.5;
        if (w > 0) {
          w *= dryF;
          if (w < 0.004) w = 0;
          wet[i] = w;
          if (w > 0) {
            if (x < nMinX) nMinX = x;
            if (y < nMinY) nMinY = y;
            if (x > nMaxX) nMaxX = x;
            if (y > nMaxY) nMaxY = y;
            if (w > maxWet) maxWet = w;
          }
        }
      }
    }
    if (maxWet <= 0) {
      _hasWet = false;
    } else {
      _wetMinX = nMinX;
      _wetMinY = nMinY;
      _wetMaxX = nMaxX;
      _wetMaxY = nMaxY;
    }
  }

  // --- texture encoding for the relief shader ---

  /// RGBA8 buffer with thickness packed 16-bit into R (high) + G (low).
  Uint8List encodeHeightRGBA() {
    final out = Uint8List(width * height * 4);
    final double inv = 1.0 / maxHeight;
    for (int i = 0, p = 0; i < thickness.length; i++, p += 4) {
      double h = (canvasHeight[i] + thickness[i]) * inv;
      if (h < 0) h = 0;
      if (h > 1) h = 1;
      final int q = (h * 65535.0).round();
      out[p] = (q >> 8) & 0xFF;
      out[p + 1] = q & 0xFF;
      out[p + 2] = 0;
      out[p + 3] = 255;
    }
    return out;
  }

  /// RGBA8 buffer of the surface pigment colour.
  Uint8List encodeAlbedoRGBA() {
    final out = Uint8List(width * height * 4);
    for (int i = 0, p = 0; i < thickness.length; i++, p += 4) {
      out[p] = (r[i] * 255.0).round().clamp(0, 255);
      out[p + 1] = (g[i] * 255.0).round().clamp(0, 255);
      out[p + 2] = (b[i] * 255.0).round().clamp(0, 255);
      out[p + 3] = 255;
    }
    return out;
  }
}

// --- Kubelka-Munk subtractive colour mixing ---
//
// Treat each RGB channel as a reflectance and mix in K/S (absorption over
// scattering) space, which is how real pigments combine. Mixing [base] with
// pigment [pig] at concentration [t] (0..1).

double _smoothstep(double edge0, double edge1, double x) {
  if (edge1 <= edge0) return x >= edge1 ? 1.0 : 0.0;
  final double t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

double _ks(double reflectance) {
  final double r = reflectance.clamp(0.004, 1.0);
  return (1.0 - r) * (1.0 - r) / (2.0 * r);
}

double _unKs(double ks) => 1.0 + ks - math.sqrt(ks * ks + 2.0 * ks);

double _kmMix(double base, double pig, double t) {
  if (t <= 0) return base;
  final double ks = _ks(base) * (1.0 - t) + _ks(pig) * t;
  return _unKs(ks).clamp(0.0, 1.0);
}
