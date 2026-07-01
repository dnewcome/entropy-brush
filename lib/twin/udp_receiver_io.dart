import 'dart:io';

/// Real loopback-UDP receiver (desktop/mobile). Binds a socket on [port] and
/// hands each datagram's bytes to [onData].
class UdpReceiver {
  UdpReceiver({required this.port, required this.onData});
  final int port;
  final void Function(List<int> data) onData;

  RawDatagramSocket? _socket;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, port);
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? dg;
      while ((dg = _socket!.receive()) != null) {
        onData(dg!.data);
      }
    });
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
  }
}
