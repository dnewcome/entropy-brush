import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../sim/paint_grid.dart';

/// Movable light + shading parameters for the relief render.
class LightSettings {
  LightSettings({
    this.azimuth = 2.4,
    this.elevation = 0.9,
    this.heightScale = 900.0,
    this.ambient = 0.4,
    this.specular = 0.35,
    this.shininess = 24.0,
    this.occlusion = 0.6,
    this.gloss = 0.5,
    this.fill = 0.4,
    this.saturation = 1.18,
  });

  /// Light direction in spherical terms. Azimuth around the canvas, elevation
  /// above it (radians).
  double azimuth;
  double elevation;

  /// Relief exaggeration — how strongly height differences bend the normal.
  double heightScale;
  double ambient;
  double specular;
  double shininess;

  /// Cavity ambient occlusion strength — crevices between strokes darken.
  double occlusion;

  /// Wet sheen amount (sharpens specular, adds broad sheen + fresnel edge).
  double gloss;

  /// Fill-light strength (softens shadows opposite the key light).
  double fill;

  /// Colour richness multiplier.
  double saturation;

  /// Direction TO the light, in the shader's space (x right, y down, z up).
  List<double> get direction {
    final double ce = math.cos(elevation);
    return [
      ce * math.cos(azimuth),
      ce * math.sin(azimuth),
      math.sin(elevation),
    ];
  }
}

/// Owns the relief [FragmentShader] and the height/albedo textures uploaded to
/// the GPU. The shader does per-pixel normal reconstruction + lighting, which
/// is the cheap path that lets us shade the whole canvas every frame.
class ReliefRenderer {
  ReliefRenderer._(this._program);

  final ui.FragmentProgram _program;
  late final ui.FragmentShader _shader = _program.fragmentShader();

  ui.Image? heightTex;
  ui.Image? albedoTex;
  bool _encoding = false;

  static Future<ReliefRenderer> load() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/relief.frag');
    return ReliefRenderer._(program);
  }

  bool get ready => heightTex != null && albedoTex != null;

  /// Re-encode the grid into GPU textures. Coalesces calls so we never have two
  /// encodes in flight. Returns once the new textures are live.
  Future<void> uploadTextures(PaintGrid grid) async {
    if (_encoding) return;
    _encoding = true;
    try {
      final h = await _decode(grid.encodeHeightRGBA(), grid.width, grid.height);
      final a = await _decode(grid.encodeAlbedoRGBA(), grid.width, grid.height);
      heightTex?.dispose();
      albedoTex?.dispose();
      heightTex = h;
      albedoTex = a;
      grid.resetDirty();
    } finally {
      _encoding = false;
    }
  }

  static const List<double> _straightView = [0.0, 0.0, 1.0];

  void _setUniforms(Size outSize, LightSettings light, double gw, double gh,
      List<double> viewDir) {
    final dir = light.direction;
    _shader
      ..setFloat(0, outSize.width)
      ..setFloat(1, outSize.height)
      ..setFloat(2, gw)
      ..setFloat(3, gh)
      ..setFloat(4, dir[0])
      ..setFloat(5, dir[1])
      ..setFloat(6, dir[2])
      ..setFloat(7, light.heightScale)
      ..setFloat(8, light.ambient)
      ..setFloat(9, light.specular)
      ..setFloat(10, light.shininess)
      ..setFloat(11, viewDir[0])
      ..setFloat(12, viewDir[1])
      ..setFloat(13, viewDir[2])
      ..setFloat(14, light.occlusion)
      ..setFloat(15, light.gloss)
      ..setFloat(16, light.fill)
      ..setFloat(17, light.saturation)
      ..setImageSampler(0, heightTex!)
      ..setImageSampler(1, albedoTex!);
  }

  /// Paint the shaded relief into [canvas] filling [size]. [viewDir] is the
  /// direction to the camera in canvas space (drives specular under tilt).
  void paint(Canvas canvas, Size size, LightSettings light,
      {List<double> viewDir = _straightView}) {
    if (!ready) return;
    _setUniforms(size, light, heightTex!.width.toDouble(),
        heightTex!.height.toDouble(), viewDir);
    canvas.drawRect(Offset.zero & size, Paint()..shader = _shader);
  }

  /// Render the shaded canvas to an offscreen image at grid resolution — used
  /// for PNG export. Rendered straight-on (no tilt) so the asset is flat.
  Future<ui.Image> renderToImage(PaintGrid grid, LightSettings light) async {
    await uploadTextures(grid);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(grid.width.toDouble(), grid.height.toDouble());
    paint(canvas, size, light);
    final picture = recorder.endRecording();
    return picture.toImage(grid.width, grid.height);
  }

  Future<ui.Image> _decode(Uint8List px, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  void dispose() {
    heightTex?.dispose();
    albedoTex?.dispose();
    _shader.dispose();
  }
}
