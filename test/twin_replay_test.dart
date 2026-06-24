// Verifies the digital-twin premise: a recorded op stream reproduces the SAME
// painting (deterministic replay), and survives a JSON round-trip unchanged.
// Mirrors PaintController's _doStart/_doMove/_doEnd driving logic.
// Run: dart run test/twin_replay_test.dart
import 'dart:math' as math;

import 'package:entropy_brush/sim/brush.dart';
import 'package:entropy_brush/sim/paint_grid.dart';
import 'package:entropy_brush/twin/twin_performance.dart';

const _dt = 1.0 / 120.0;
const _sub = 1.5;
const _maxSteps = 64;

PaintGrid render(TwinPerformance p) {
  final grid = PaintGrid(p.gridSize, p.gridSize);
  final brush = Brush(BrushConfig());
  brush.setPigment(0.12, 0.20, 0.62);
  brush.reload();
  double lastX = 0, lastY = 0;
  bool hasLast = false;

  for (final op in p.ops) {
    switch (op.kind) {
      case TwinOpKind.down:
        brush.begin(StrokeSample(op.x, op.y, pressure: op.pressure));
        lastX = op.x;
        lastY = op.y;
        hasLast = true;
        break;
      case TwinOpKind.move:
        if (!hasLast) {
          brush.begin(StrokeSample(op.x, op.y, pressure: op.pressure));
          lastX = op.x;
          lastY = op.y;
          hasLast = true;
          break;
        }
        final dx = op.x - lastX, dy = op.y - lastY;
        final dist = math.sqrt(dx * dx + dy * dy);
        final steps = math.max(1, math.min(_maxSteps, (dist / _sub).ceil()));
        for (int i = 1; i <= steps; i++) {
          final t = i / steps;
          brush.step(
              StrokeSample(lastX + dx * t, lastY + dy * t,
                  pressure: op.pressure),
              _dt,
              grid);
        }
        lastX = op.x;
        lastY = op.y;
        break;
      case TwinOpKind.up:
        brush.end();
        hasLast = false;
        break;
      case TwinOpKind.reload:
        brush.setPigment(op.r, op.g, op.b);
        brush.reload();
        break;
    }
  }
  return grid;
}

double checksum(PaintGrid g) {
  double s = 0;
  for (int i = 0; i < g.thickness.length; i++) {
    s += g.thickness[i] * (1 + (i % 7));
  }
  return s;
}

void main() {
  // A small scripted performance: two strokes with a reload between.
  final ops = <TwinOp>[
    TwinOp(0.0, TwinOpKind.down, x: 100, y: 300, pressure: 0.9),
    for (int i = 1; i <= 30; i++)
      TwinOp(i * 0.02, TwinOpKind.move, x: 100.0 + i * 12, y: 300, pressure: 0.9),
    TwinOp(0.7, TwinOpKind.up),
    TwinOp(0.8, TwinOpKind.reload, r: 0.92, g: 0.78, b: 0.12),
    TwinOp(0.9, TwinOpKind.down, x: 200, y: 120, pressure: 0.7),
    for (int i = 1; i <= 30; i++)
      TwinOp(0.9 + i * 0.02, TwinOpKind.move,
          x: 200, y: 120.0 + i * 12, pressure: 0.7),
    TwinOp(1.6, TwinOpKind.up),
  ];
  final perf = TwinPerformance(768, ops);

  final a = checksum(render(perf));
  final b = checksum(render(perf));
  print('deterministic replay: ${a == b}  (a=$a)');

  final roundTrip = TwinPerformance.decode(perf.encode());
  final c = checksum(render(roundTrip));
  print('json round-trip identical: ${a == c}');
  print('ops=${perf.ops.length}  strokes=${perf.strokeCount}  '
      'duration=${perf.duration}s');
}
