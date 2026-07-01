// Export facade. Desktop writes files to `~/entropybrush-exports`; web streams
// each export to a browser download. Selected by conditional import so the web
// bundle never pulls in `dart:io`.
export 'exporter_io.dart' if (dart.library.html) 'exporter_web.dart';
