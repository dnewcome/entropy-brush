// Verifies CameraInput maps normalized webcam coords to grid space and edge-
// detects pinch -> stroke start/move/end. Run: dart run test/camera_input_test.dart
import 'package:entropy_brush/twin/camera_input.dart';

void main() {
  final starts = <List<double>>[];
  final moves = <List<double>>[];
  int ends = 0;

  final cam = CameraInput(
    gridWidth: 768,
    gridHeight: 768,
    onStart: (x, y, p) => starts.add([x, y, p]),
    onMove: (x, y, p) => moves.add([x, y, p]),
    onEnd: () => ends++,
  );

  cam.ingest({'x': 0.5, 'y': 0.5, 'down': false}); // hovering, no contact
  cam.ingest({'x': 0.5, 'y': 0.5, 'down': true, 'pressure': 0.8}); // pinch down
  for (var k = 1; k <= 5; k++) {
    cam.ingest({'x': 0.5 + 0.05 * k, 'y': 0.5, 'down': true, 'pressure': 0.8});
  }
  cam.ingest({'x': 0.8, 'y': 0.5, 'down': false}); // release

  print('starts=${starts.length} (expect 1)');
  print('first start mapped to center: '
      '${starts.first[0] == 384.0 && starts.first[1] == 384.0}');
  print('moves=${moves.length} (expect 5): ${moves.length == 5}');
  print('ends=$ends (expect 1)');
  print('pressure forwarded: ${starts.first[2] == 0.8}');
  // A second hover-without-pinch must NOT start a new stroke.
  cam.ingest({'x': 0.2, 'y': 0.2, 'down': false});
  print('no phantom stroke on hover: ${starts.length == 1 && ends == 1}');
}
