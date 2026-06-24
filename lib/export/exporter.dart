import 'dart:io';
import 'dart:ui' as ui;

import '../render/relief_renderer.dart';
import '../sim/paint_grid.dart';
import '../twin/twin_performance.dart';
import 'glb_export.dart';
import 'stl_export.dart';

/// Writes PNG (shaded colour) and GLB (relief mesh) assets to a predictable
/// export folder, returning the paths so the UI can report them.
class Exporter {
  /// Resolve (and create) the export directory: ~/entropy-brush-exports.
  static Directory exportDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    final dir = Directory('$home/entropy-brush-exports');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _stamp() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p(n.month)}${p(n.day)}-${p(n.hour)}${p(n.minute)}${p(n.second)}';
  }

  /// Render the shaded canvas and save it as PNG. Returns the file path.
  static Future<String> savePng(PaintGrid grid, ReliefRenderer renderer,
      LightSettings light) async {
    final ui.Image img = await renderer.renderToImage(grid, light);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data == null) throw StateError('PNG encode failed');
    final path = '${exportDir().path}/paint-${_stamp()}.png';
    await File(path).writeAsBytes(data.buffer.asUint8List());
    return path;
  }

  /// Build and save the relief mesh as GLB. Returns the file path.
  static Future<String> saveGlb(PaintGrid grid) async {
    final bytes = buildGlb(grid);
    final path = '${exportDir().path}/relief-${_stamp()}.glb';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Build and save the relief as a watertight binary STL. Returns the path.
  static Future<String> saveStl(PaintGrid grid) async {
    final bytes = buildStl(grid);
    final path = '${exportDir().path}/relief-${_stamp()}.stl';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Save a recorded performance ("print") as JSON for later replay or G-code.
  static Future<String> savePerformance(TwinPerformance perf) async {
    final path = '${exportDir().path}/print-${_stamp()}.json';
    await File(path).writeAsString(perf.encode());
    return path;
  }
}
