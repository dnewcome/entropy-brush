// A tiny loopback-UDP datagram receiver, behind a conditional import so the
// desktop build gets the real `dart:io` socket and the web build gets a no-op
// stub (web has no `dart:io`). This is what keeps the SpaceMouse / camera
// sidecar inputs from dragging `dart:io` into the web bundle.
export 'udp_receiver_stub.dart' if (dart.library.io) 'udp_receiver_io.dart';
