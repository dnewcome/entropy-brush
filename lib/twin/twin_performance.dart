import 'dart:convert';

/// One recorded action in a painting performance. The timeline of these IS the
/// digital twin: replay them through the sim to reproduce the painting, or
/// later translate them into machine motion (G-code) for a physical print.
enum TwinOpKind { down, move, up, reload }

class TwinOp {
  TwinOp(
    this.t,
    this.kind, {
    this.x = 0,
    this.y = 0,
    this.pressure = 1.0,
    this.r = 0,
    this.g = 0,
    this.b = 0,
  });

  /// Seconds from the start of the recording.
  final double t;
  final TwinOpKind kind;

  /// Stroke position in grid coordinates, and contact pressure (0..1). For a
  /// 3-axis machine, pressure maps to Z depth.
  final double x, y, pressure;

  /// Pigment colour for a [TwinOpKind.reload].
  final double r, g, b;

  Map<String, dynamic> toJson() => {
        't': t,
        'k': kind.index,
        if (kind != TwinOpKind.reload) ...{
          'x': x,
          'y': y,
          'p': pressure,
        },
        if (kind == TwinOpKind.reload) ...{
          'r': r,
          'g': g,
          'b': b,
        },
      };

  factory TwinOp.fromJson(Map<String, dynamic> j) => TwinOp(
        (j['t'] as num).toDouble(),
        TwinOpKind.values[j['k'] as int],
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        pressure: (j['p'] as num?)?.toDouble() ?? 1.0,
        r: (j['r'] as num?)?.toDouble() ?? 0,
        g: (j['g'] as num?)?.toDouble() ?? 0,
        b: (j['b'] as num?)?.toDouble() ?? 0,
      );
}

/// A complete recorded painting: the grid it was made on plus the ordered ops.
/// This is the portable "print" — save it, replay it, or compile it to G-code.
class TwinPerformance {
  TwinPerformance(this.gridSize, this.ops);

  final int gridSize;
  final List<TwinOp> ops;

  double get duration => ops.isEmpty ? 0 : ops.last.t;
  int get strokeCount =>
      ops.where((o) => o.kind == TwinOpKind.down).length;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'gridSize': gridSize,
        'ops': ops.map((o) => o.toJson()).toList(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory TwinPerformance.decode(String s) {
    final j = json.decode(s) as Map<String, dynamic>;
    return TwinPerformance(
      j['gridSize'] as int,
      (j['ops'] as List)
          .map((e) => TwinOp.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
