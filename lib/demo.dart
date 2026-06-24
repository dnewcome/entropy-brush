import 'dart:io';
import 'dart:math' as math;

import 'paint_controller.dart';

/// Scripted self-test: drive a few strokes through the real controller, then
/// export PNG + GLB and quit. Triggered with ENTROPY_DEMO=1 so we can verify
/// the sim end-to-end without a human at the mouse.
Future<void> runDemo(PaintController c) async {
  final g = c.grid.width.toDouble();

  // Stroke 1: a fast sweeping S-curve in ultramarine — should show bristle
  // trailing and load depletion toward the end (drybrush tail).
  c.setPigment(0.12, 0.20, 0.62);
  c.reloadBrush();
  _curve(c, (t) {
    final x = g * (0.12 + 0.76 * t);
    final y = g * (0.35 + 0.18 * math.sin(t * math.pi * 2));
    return Offset(x, y);
  }, steps: 90);

  // Stroke 2: cadmium yellow crossing it — overlap should mix wet-on-wet to
  // green, and pile thicker where strokes cross (impasto).
  c.setPigment(0.92, 0.78, 0.12);
  c.reloadBrush();
  _curve(c, (t) {
    final x = g * (0.30 + 0.40 * t);
    final y = g * (0.15 + 0.65 * t);
    return Offset(x, y);
  }, steps: 70);

  // Stroke 3: a short loaded dab of red to show a fat blob.
  c.setPigment(0.78, 0.12, 0.10);
  c.reloadBrush();
  c.brush.config.loadCapacity = 2.5;
  c.reloadBrush();
  _curve(c, (t) {
    final x = g * (0.62 + 0.06 * math.cos(t * math.pi * 2));
    final y = g * (0.70 + 0.06 * math.sin(t * math.pi * 2));
    return Offset(x, y);
  }, steps: 40);

  stdout.writeln('[demo] avg load after strokes: '
      '${c.brush.averageLoad.toStringAsFixed(3)}');

  final png = await c.exportPng();
  final glb = await c.exportGlb();
  stdout.writeln('[demo] PNG: $png');
  stdout.writeln('[demo] GLB: $glb');
  stdout.writeln('[demo] done');
  exit(0);
}

void _curve(PaintController c, Offset Function(double t) path,
    {required int steps}) {
  final p0 = path(0);
  c.strokeStart(p0.dx, p0.dy);
  for (int i = 1; i <= steps; i++) {
    final p = path(i / steps);
    c.strokeMove(p.dx, p.dy);
  }
  c.strokeEnd();
}

class Offset {
  const Offset(this.dx, this.dy);
  final double dx, dy;
}
