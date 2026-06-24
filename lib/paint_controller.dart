import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'export/exporter.dart';
import 'render/relief_renderer.dart';
import 'sim/brush.dart';
import 'sim/paint_grid.dart';
import 'sim/paint_profile.dart';
import 'twin/camera_input.dart';
import 'twin/spacemouse_input.dart';
import 'twin/twin_performance.dart';

/// Ties the input, the bristle brush, the height-field grid and the relief
/// renderer together. The widget feeds it pointer samples in *grid* coordinates
/// and pumps [frame] once per vsync; everything else lives here.
class PaintController extends ChangeNotifier {
  PaintController({int gridSize = 768, int paletteSize = 240})
      : grid = PaintGrid(gridSize, gridSize),
        palette = PaintGrid(paletteSize, paletteSize, maxHeight: 4.0)
          ..profile = PaintProfile(body: 1.0, lumpiness: 0.0, opacity: 1.4)
          ..generateCanvasTexture(amplitude: 0.0), // palette stays smooth
        brush = Brush(BrushConfig());

  final PaintGrid grid;
  final Brush brush;
  final LightSettings light = LightSettings();

  /// The mixing palette: a second canvas where pigments blend so you can load
  /// the brush with a custom colour.
  final PaintGrid palette;

  /// Lightly raked lighting for the palette so squeezed blobs of paint read as
  /// dimensional mounds (but flatter than the main canvas).
  final LightSettings paletteLight = LightSettings(
      ambient: 0.78, heightScale: 320, specular: 0.18, elevation: 1.0);

  ReliefRenderer? renderer;
  ReliefRenderer? paletteRenderer;
  bool get rendererReady => renderer?.ready ?? false;

  /// The painting rendered flat to an image; the slab view textures this onto
  /// its top face. Re-rendered when the canvas or light changes.
  ui.Image? reliefImage;
  bool _renderingImage = false;

  /// Canvas slab thickness, as a fraction of the canvas width.
  double canvasThicknessFrac = 0.06;

  void _requestReliefImage() {
    final r = renderer;
    if (r == null || !r.ready || _renderingImage) return;
    _renderingImage = true;
    r.renderToImage(grid, light).then((img) {
      reliefImage?.dispose();
      reliefImage = img;
      _renderingImage = false;
      notifyListeners();
    });
  }

  // --- view: tilt, zoom, pan ---
  double tiltX = 0.0; // pitch, radians
  double tiltY = 0.0; // yaw, radians
  double perspective = 0.0012;
  double zoom = 1.0;
  double panX = 0.0;
  double panY = 0.0;
  double canvasRoll = 0.0; // in-plane spin of the canvas (radians)

  void viewChanged() => notifyListeners();

  // --- canvas substrate texture (Perlin relief) ---
  double canvasAmplitude = 0.08;
  double canvasScale = 0.16;
  int _canvasSeed = 1;

  void applyCanvasTexture() {
    grid.generateCanvasTexture(
        amplitude: canvasAmplitude, scale: canvasScale, seed: _canvasSeed);
    _requestReliefImage();
    notifyListeners();
  }

  void newCanvasTexture() {
    _canvasSeed++;
    applyCanvasTexture();
  }

  /// Direction to the camera expressed in the canvas's own frame, given the
  /// current tilt. Feeds the shader so specular highlights shift with tilt.
  List<double> get viewDir {
    final double cx = math.cos(tiltX);
    return [
      -cx * math.sin(tiltY),
      math.sin(tiltX),
      cx * math.cos(tiltY),
    ];
  }

  void tiltChanged() => notifyListeners();

  // Current pigment, shared by the swatch picker and palette mixing.
  double _curR = 0.12, _curG = 0.20, _curB = 0.62;

  // Fixed simulation step keeps the bristle springs stable regardless of how
  // fast pointer events arrive. Fast strokes simply take more substeps.
  static const double _simDt = 1.0 / 120.0;
  static const double _substepPx = 1.5;
  static const int _maxSubsteps = 64;

  double _pressure = 1.0;
  double get pressure => _pressure;
  set pressure(double v) {
    _pressure = v.clamp(0.05, 1.0);
  }

  bool _hasLast = false;
  double _lastX = 0, _lastY = 0;
  bool _stroking = false;

  // --- twin recorder & replay state ---
  final List<TwinOp> _recOps = [];
  final Stopwatch _recClock = Stopwatch();
  bool _recording = false;

  TwinPerformance? _lastPerformance;
  TwinPerformance? get lastPerformance => _lastPerformance;

  TwinPerformance? _replayPerf;
  int _replayIdx = 0;
  final Stopwatch _replayClock = Stopwatch();
  bool _replaying = false;

  bool get recording => _recording;
  bool get replaying => _replaying;

  double get _now => _recording ? _recClock.elapsedMicroseconds / 1e6 : 0.0;
  void _rec(TwinOp op) {
    if (_recording) _recOps.add(op);
  }

  /// Non-null if the relief shader failed to load (e.g. stale asset bundle —
  /// do a full restart, not hot reload). The UI shows this instead of crashing.
  String? rendererError;

  Future<void> attachRenderer() async {
    try {
      renderer = await ReliefRenderer.load();
      await renderer!.uploadTextures(grid);
      paletteRenderer = await ReliefRenderer.load();
      await paletteRenderer!.uploadTextures(palette);
      _requestReliefImage();
    } catch (e) {
      rendererError = 'Could not load relief shader: $e\n'
          'Fully restart the app (stop and re-run; hot reload does not '
          're-bundle assets).';
      debugPrint(rendererError);
    }
    notifyListeners();
  }

  void setPigment(double r, double g, double b) {
    _curR = r;
    _curG = g;
    _curB = b;
    brush.setPigment(r, g, b);
  }

  void reloadBrush() {
    final c = brush.loadColor;
    _rec(TwinOp(_now, TwinOpKind.reload, r: c[0], g: c[1], b: c[2]));
    brush.reload();
  }

  void rebuildBristles() => brush.rebuildBristles();

  // --- input seam -----------------------------------------------------------
  // The public stroke methods are the single point every input source (mouse,
  // stylus, depth-camera arm tracking) feeds into. [pressure] is first-class so
  // a tracker can supply contact force; the mouse falls back to the slider.
  // Each public call records a TwinOp, then drives the sim via a private _do
  // method that replay also calls (without recording).

  void strokeStart(double gx, double gy, {double? pressure}) {
    final pr = pressure ?? _pressure;
    _rec(TwinOp(_now, TwinOpKind.down, x: gx, y: gy, pressure: pr));
    _doStart(gx, gy, pr);
  }

  void strokeMove(double gx, double gy, {double? pressure}) {
    final pr = pressure ?? _pressure;
    _rec(TwinOp(_now, TwinOpKind.move, x: gx, y: gy, pressure: pr));
    _doMove(gx, gy, pr);
  }

  void strokeEnd() {
    _rec(TwinOp(_now, TwinOpKind.up));
    _doEnd();
  }

  void _doStart(double gx, double gy, double pr) {
    brush.begin(StrokeSample(gx, gy, pressure: pr));
    _lastX = gx;
    _lastY = gy;
    _hasLast = true;
    _stroking = true;
  }

  void _doMove(double gx, double gy, double pr) {
    if (!_hasLast) {
      _doStart(gx, gy, pr);
      return;
    }
    final double dx = gx - _lastX;
    final double dy = gy - _lastY;
    final double dist = math.sqrt(dx * dx + dy * dy);
    final int steps =
        math.max(1, math.min(_maxSubsteps, (dist / _substepPx).ceil()));
    for (int i = 1; i <= steps; i++) {
      final double t = i / steps;
      brush.step(
        StrokeSample(_lastX + dx * t, _lastY + dy * t, pressure: pr),
        _simDt,
        grid,
      );
    }
    _lastX = gx;
    _lastY = gy;
  }

  void _doEnd() {
    brush.end();
    _stroking = false;
    _hasLast = false;
  }

  void clearCanvas() {
    grid.clear();
    _requestReliefImage();
  }

  // --- palette: mix pigments, then load the brush from the mix ---

  double _palLastX = 0, _palLastY = 0;
  bool _palHasPos = false;

  // Squeezing paint from the tube: while the pen is held on the palette we keep
  // depositing every frame, so a long press grows a blob even without moving.
  bool _squirting = false;
  double _squirtAccum = 0;

  static const double _squirtVolPerFrame = 1.2;
  static const double _squirtMaxRadius = 16.0;

  void paletteSquirtStart(double gx, double gy) {
    _squirting = true;
    _squirtAccum = 0;
    _palLastX = gx;
    _palLastY = gy;
    _palHasPos = true;
  }

  void paletteSquirtMove(double gx, double gy) {
    _palLastX = gx;
    _palLastY = gy;
    _palHasPos = true;
  }

  void paletteSquirtEnd() => _squirting = false;

  /// Emit one frame's worth of paint at the held spot. The blob spreads as more
  /// comes out, like a bead squeezed from a tube.
  void _squirt() {
    _squirtAccum += _squirtVolPerFrame;
    // Spread up to a cap, then keep depositing so the bead mounds up instead of
    // flattening into a puddle.
    final double radius =
        math.min(_squirtMaxRadius, 6.0 + math.sqrt(_squirtAccum) * 1.8);
    palette.deposit(
        _palLastX, _palLastY, radius, _squirtVolPerFrame, _curR, _curG, _curB);
  }

  /// Dip the brush into the palette at the last touched spot: the brush takes
  /// on the mixed colour there and refills to a full load.
  void loadBrushFromPalette() {
    final px = _palHasPos ? _palLastX : palette.width / 2;
    final py = _palHasPos ? _palLastY : palette.height / 2;
    final rgb = <double>[_curR, _curG, _curB];
    final amount = palette.sampleColor(px, py, 12.0, rgb);
    if (amount > 0) {
      setPigment(rgb[0], rgb[1], rgb[2]);
    }
    final c = brush.loadColor;
    _rec(TwinOp(_now, TwinOpKind.reload, r: c[0], g: c[1], b: c[2]));
    brush.reload();
    notifyListeners();
  }

  // --- twin: record a performance, then replay it (this is a "print") --------

  void startRecording() {
    if (_replaying) return;
    _recOps.clear();
    _recClock
      ..reset()
      ..start();
    _recording = true;
    notifyListeners();
  }

  TwinPerformance stopRecording() {
    _recording = false;
    _recClock.stop();
    final perf =
        TwinPerformance(grid.width, List<TwinOp>.of(_recOps), sizeMm: exportSizeMm);
    _lastPerformance = perf;
    notifyListeners();
    return perf;
  }

  /// Replay [perf] (defaults to the last recording) deterministically through
  /// the sim, in real time. Clears the canvas first so the print reproduces.
  void startReplay([TwinPerformance? perf]) {
    final p = perf ?? _lastPerformance;
    if (p == null || _recording) return;
    grid.clear();
    _doEnd();
    _replayPerf = p;
    _replayIdx = 0;
    _replaying = true;
    _replayClock
      ..reset()
      ..start();
    notifyListeners();
  }

  void stopReplay() {
    _replaying = false;
    _replayClock.stop();
    _doEnd();
    notifyListeners();
  }

  void _advanceReplay() {
    final p = _replayPerf;
    if (p == null) return;
    final double t = _replayClock.elapsedMicroseconds / 1e6;
    while (_replayIdx < p.ops.length && p.ops[_replayIdx].t <= t) {
      final op = p.ops[_replayIdx++];
      switch (op.kind) {
        case TwinOpKind.down:
          _doStart(op.x, op.y, op.pressure);
          break;
        case TwinOpKind.move:
          _doMove(op.x, op.y, op.pressure);
          break;
        case TwinOpKind.up:
          _doEnd();
          break;
        case TwinOpKind.reload:
          brush.setPigment(op.r, op.g, op.b);
          brush.reload();
          break;
      }
    }
    if (_replayIdx >= p.ops.length) {
      _replaying = false;
      _replayClock.stop();
      _doEnd();
      notifyListeners();
    }
  }

  void clearPalette() {
    palette.clear();
    _palHasPos = false;
    _requestPaletteUpload();
  }

  // --- SpaceMouse (6DOF view navigation) ---
  SpaceMouseInput? _spaceMouse;
  bool get spaceMouseOn => _spaceMouse != null;
  String? spaceMouseStatus;
  // Separate sensitivities (zoom was too hot, pan too sluggish).
  double smPanSpeed = 1.8;
  double smZoomSpeed = 0.6;
  double smTiltSpeed = 1.2;

  Future<void> toggleSpaceMouse() async {
    if (_spaceMouse != null) {
      await _spaceMouse!.stop();
      _spaceMouse = null;
      spaceMouseStatus = null;
    } else {
      final sm = SpaceMouseInput();
      try {
        await sm.start();
        _spaceMouse = sm;
        spaceMouseStatus = 'listening · run tools/spacemouse.py';
      } catch (e) {
        spaceMouseStatus = 'could not open UDP ${sm.port}: $e';
      }
    }
    notifyListeners();
  }

  // Integrate the latest SpaceMouse axes into the view over [dt]. Returns true
  // if the view moved (so the frame loop knows to repaint).
  bool _applySpaceMouse(double dt) {
    final sm = _spaceMouse;
    if (sm == null || !sm.active) return false;
    // SpaceMouse translation:
    //   push/pull the cap (Y, toward/away)  → zoom
    //   slide left/right (X)                → pan X
    //   lift/press the cap (Z, up/down)     → pan Y
    if (sm.ty != 0) {
      zoom = (zoom * math.exp(sm.ty * smZoomSpeed * dt)).clamp(0.5, 12.0);
    }
    panX = (panX + sm.tx * smPanSpeed * dt).clamp(-1.5, 1.5);
    panY = (panY - sm.tz * smPanSpeed * dt).clamp(-1.5, 1.5);
    // Rotation: twist (ry) spins the canvas; tilt fwd/back (rx) → tiltX;
    // tilt left/right (rz) → tiltY.
    canvasRoll += sm.ry * smTiltSpeed * dt;
    tiltX = (tiltX + sm.rx * smTiltSpeed * dt).clamp(-0.8, 0.8);
    tiltY = (tiltY + sm.rz * smTiltSpeed * dt).clamp(-0.8, 0.8);
    if (sm.button0) {
      tiltX = 0;
      tiltY = 0;
      zoom = 1.0;
      panX = 0;
      panY = 0;
    }
    return true;
  }

  // --- wet-paint flow ---
  double flowRate = 0.4; // 0..1 leveling/oozing strength (drives substep count)
  double dryTime = 3.0; // seconds for wet paint to mostly set
  final Stopwatch _frameClock = Stopwatch()..start();

  /// Pump one frame: advance replay/squeeze, run wet-paint flow, then refresh
  /// GPU textures for whichever surface changed.
  void frame() {
    if (_replaying) _advanceReplay();
    if (_squirting) _squirt();

    double dt = _frameClock.elapsedMicroseconds / 1e6;
    _frameClock
      ..reset()
      ..start();
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;
    if (_applySpaceMouse(dt)) notifyListeners();
    // Strength drives how many leveling substeps run per frame (each capped for
    // stability), so high flow gives obvious oozing without going unstable.
    if (flowRate > 0.01) {
      final int iters = math.max(1, (flowRate * 6).round());
      final double sdt = dt / iters;
      for (int it = 0; it < iters; it++) {
        grid.flowStep(sdt, flow: 0.2, dryTime: dryTime);
        palette.flowStep(sdt, flow: 0.16, dryTime: dryTime * 0.6);
      }
    }

    if (grid.isDirty) _requestReliefImage();
    if (palette.isDirty) _requestPaletteUpload();
  }

  bool _palUploading = false;
  void _requestPaletteUpload() {
    final r = paletteRenderer;
    if (r == null || _palUploading) return;
    _palUploading = true;
    r.uploadTextures(palette).then((_) {
      _palUploading = false;
      notifyListeners();
    });
  }

  void lightChanged() {
    _requestReliefImage();
    notifyListeners();
  }

  // --- exports ---

  // Real-world export scale (mm), shared by GLB + STL.
  double exportSizeMm = 100.0; // longer side
  double exportReliefMm = 6.0; // tallest impasto height
  double exportBaseMm = 2.0; // STL base plate
  int exportResolution = 256; // mesh grid resolution

  Future<String> exportPng() => Exporter.savePng(grid, renderer!, light);
  Future<String> exportGlb() => Exporter.saveGlb(grid,
      resolution: exportResolution,
      sizeMm: exportSizeMm,
      reliefMm: exportReliefMm);
  Future<String> exportStl() => Exporter.saveStl(grid,
      resolution: exportResolution,
      sizeMm: exportSizeMm,
      reliefMm: exportReliefMm,
      baseMm: exportBaseMm);

  Future<String> savePerformance() {
    final p = _lastPerformance;
    if (p == null) throw StateError('No recorded performance yet');
    return Exporter.savePerformance(p);
  }

  // --- webcam hand-tracking input -------------------------------------------

  CameraInput? _camera;
  bool get cameraOn => _camera != null;
  String? cameraStatus;

  Future<void> toggleCamera() async {
    if (_camera != null) {
      await _camera!.stop();
      _camera = null;
      cameraStatus = null;
    } else {
      final cam = CameraInput(
        gridWidth: grid.width.toDouble(),
        gridHeight: grid.height.toDouble(),
        onStart: (x, y, p) => strokeStart(x, y, pressure: p),
        onMove: (x, y, p) => strokeMove(x, y, pressure: p),
        onEnd: strokeEnd,
      );
      try {
        await cam.start();
        _camera = cam;
        cameraStatus = 'listening · run tools/hand_tracker.py · pinch to paint';
      } catch (e) {
        cameraStatus = 'could not open UDP ${cam.port}: $e';
      }
    }
    notifyListeners();
  }

  bool get stroking => _stroking;

  @override
  void dispose() {
    _camera?.stop();
    _spaceMouse?.stop();
    reliefImage?.dispose();
    renderer?.dispose();
    paletteRenderer?.dispose();
    super.dispose();
  }
}
