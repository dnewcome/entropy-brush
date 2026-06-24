import 'package:flutter/material.dart';

import '../paint_controller.dart';
import 'paint_canvas.dart';

/// The mixing palette: drag the current pigment on to blend colours, then load
/// the brush from the mix. Flat-lit (it's about colour, not relief).
class PaletteCanvas extends StatelessWidget {
  const PaletteCanvas({super.key, required this.controller});

  final PaintController controller;

  void _at(Offset local, Size size, void Function(double, double) fn) {
    final gx = (local.dx / size.width * controller.palette.width)
        .clamp(0.0, controller.palette.width - 1.0);
    final gy = (local.dy / size.height * controller.palette.height)
        .clamp(0.0, controller.palette.height - 1.0);
    fn(gx, gy);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF3A3A40)),
              ),
              child: Listener(
                onPointerDown: (e) =>
                    _at(e.localPosition, size, controller.paletteSquirtStart),
                onPointerMove: (e) {
                  if (e.buttons != 0) {
                    _at(e.localPosition, size, controller.paletteSquirtMove);
                  }
                },
                onPointerUp: (e) => controller.paletteSquirtEnd(),
                onPointerCancel: (e) => controller.paletteSquirtEnd(),
                child: CustomPaint(
                  painter: ReliefPainter(
                    repaintOn: controller,
                    renderer: controller.paletteRenderer,
                    light: controller.paletteLight,
                  ),
                  size: size,
                  willChange: true,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
