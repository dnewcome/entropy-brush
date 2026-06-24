import 'package:entropy_brush/twin/spacemouse_input.dart';
void main() {
  final sm = SpaceMouseInput();
  // Small jitter inside the deadzone is ignored.
  sm.ingest({'tx': 0.03, 'ty': -0.04, 'tz': 0.0, 'rx': 0.02, 'ry': 0.0, 'rz': 0.0});
  print('deadzone suppresses jitter: ${!sm.active}');
  // A real push registers; buttons parse.
  sm.ingest({'tx': 0.5, 'ty': 0.0, 'tz': -0.3, 'rx': 0.0, 'ry': 0.2, 'rz': -0.4, 'buttons': [1, 0]});
  print('axes parsed: tx=${sm.tx}, tz=${sm.tz}, ry=${sm.ry}, rz=${sm.rz}');
  print('active past deadzone: ${sm.active}');
  print('button0 pressed: ${sm.button0}');
  // Clamps out-of-range values.
  sm.ingest({'tx': 2.5});
  print('clamps to <=1: ${sm.tx <= 1.0}');
}
