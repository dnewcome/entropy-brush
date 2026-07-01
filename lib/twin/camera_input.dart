import 'dart:async';
import 'dart:convert';

import 'udp_receiver.dart';

/// Receives hand-tracking packets from the Python webcam sidecar over UDP and
/// turns them into strokes on the input seam. This is the same shape a
/// depth-camera (RealSense) source will take: an external tracker streams
/// {x, y, down, pressure}; we smooth it and edge-detect contact into
/// start/move/end calls.
///
/// Packet (one JSON object per datagram):
///   { "x": 0.0..1, "y": 0.0..1, "down": bool, "pressure": 0.0..1 }
/// x,y are normalised in the (already mirrored) camera frame.
class CameraInput {
  CameraInput({
    required this.gridWidth,
    required this.gridHeight,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    this.port = 5005,
    this.smoothing = 0.4,
  });

  final double gridWidth, gridHeight;
  final void Function(double gx, double gy, double pressure) onStart;
  final void Function(double gx, double gy, double pressure) onMove;
  final void Function() onEnd;
  final int port;

  /// EMA factor for the noisy landmark position (0 = frozen, 1 = no smoothing).
  final double smoothing;

  UdpReceiver? _receiver;

  bool _down = false;
  bool _have = false;
  double _sx = 0, _sy = 0;

  Future<void> start() async {
    final r = UdpReceiver(
      port: port,
      onData: (data) {
        try {
          ingest(json.decode(utf8.decode(data)) as Map<String, dynamic>);
        } catch (_) {
          // ignore malformed packets
        }
      },
    );
    await r.start();
    _receiver = r;
  }

  Future<void> stop() async {
    if (_down) {
      onEnd();
      _down = false;
    }
    await _receiver?.stop();
    _receiver = null;
    _have = false;
  }

  /// Process one tracking packet. Public so the mapping + contact edge logic can
  /// be unit-tested without a live socket.
  void ingest(Map<String, dynamic> j) {
    final bool down = j['down'] == true;
    final double x = ((j['x'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
    final double y = ((j['y'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
    final double pressure =
        ((j['pressure'] as num?)?.toDouble() ?? 0.8).clamp(0.05, 1.0);

    // Smooth the landmark; snap on a fresh contact so the first dab is crisp.
    if (!_have || (down && !_down)) {
      _sx = x;
      _sy = y;
      _have = true;
    } else {
      _sx += (x - _sx) * smoothing;
      _sy += (y - _sy) * smoothing;
    }

    final double gx = (_sx * gridWidth).clamp(0.0, gridWidth - 1);
    final double gy = (_sy * gridHeight).clamp(0.0, gridHeight - 1);

    if (down && !_down) {
      _down = true;
      onStart(gx, gy, pressure);
    } else if (down && _down) {
      onMove(gx, gy, pressure);
    } else if (!down && _down) {
      _down = false;
      onEnd();
    }
  }
}
