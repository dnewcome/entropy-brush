/// Web stub: there is no `dart:io` UDP on the web, so starting a sidecar
/// receiver is unsupported. Same API as the io version; `start()` throws a
/// clear error that the controller catches and surfaces as a status message.
class UdpReceiver {
  UdpReceiver({required this.port, required this.onData});
  final int port;
  final void Function(List<int> data) onData;

  Future<void> start() async {
    throw UnsupportedError('Sidecar UDP input is not available in the browser');
  }

  Future<void> stop() async {}
}
