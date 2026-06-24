import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Receives 3Dconnexion SpaceMouse 6DOF state from the Python sidecar over UDP.
/// The axes are continuous displacements (-1..1 while held); the controller
/// integrates them into the view (pan / zoom / tilt) each frame.
///
/// Packet: {"tx","ty","tz","rx","ry","rz": -1..1, "buttons":[0/1,...]}
class SpaceMouseInput {
  SpaceMouseInput({this.port = 5006});
  final int port;

  RawDatagramSocket? _socket;

  // Latest axis state (translation x/y/z, rotation roll/pitch/yaw), deadzoned.
  double tx = 0, ty = 0, tz = 0;
  double rx = 0, ry = 0, rz = 0;
  bool button0 = false, button1 = false;

  static const double _deadzone = 0.06;
  double _dz(double v) => v.abs() < _deadzone ? 0.0 : v;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, port);
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? dg;
      while ((dg = _socket!.receive()) != null) {
        try {
          ingest(json.decode(utf8.decode(dg!.data)) as Map<String, dynamic>);
        } catch (_) {
          // ignore malformed packets
        }
      }
    });
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    tx = ty = tz = rx = ry = rz = 0;
    button0 = button1 = false;
  }

  /// Parse one packet. Public so deadzone/mapping can be unit-tested.
  void ingest(Map<String, dynamic> j) {
    double f(String k) => ((j[k] as num?)?.toDouble() ?? 0).clamp(-1.0, 1.0);
    tx = _dz(f('tx'));
    ty = _dz(f('ty'));
    tz = _dz(f('tz'));
    rx = _dz(f('rx'));
    ry = _dz(f('ry'));
    rz = _dz(f('rz'));
    final b = j['buttons'];
    button0 = b is List && b.isNotEmpty && (b[0] == 1 || b[0] == true);
    button1 = b is List && b.length > 1 && (b[1] == 1 || b[1] == true);
  }

  /// True if any axis is currently displaced past the deadzone.
  bool get active =>
      tx != 0 || ty != 0 || tz != 0 || rx != 0 || ry != 0 || rz != 0;
}
