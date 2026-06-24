import 'package:flutter/material.dart';

import '../paint_controller.dart';
import '../render/relief_renderer.dart';

/// The painting surface. Keeps a square aspect so the square grid maps to the
/// view without distortion, forwards pointer input (converted to grid
/// coordinates) to the controller, and tips in 3D under the tilt transform.
class PaintCanvas extends StatelessWidget {
  const PaintCanvas({super.key, required this.controller});

  final PaintController controller;

  void _send(Offset local, Size size, void Function(double, double) fn) {
    final double gx = (local.dx / size.width * controller.grid.width)
        .clamp(0.0, controller.grid.width - 1.0);
    final double gy = (local.dy / size.height * controller.grid.height)
        .clamp(0.0, controller.grid.height - 1.0);
    fn(gx, gy);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            // Rebuild on every controller notify so the tilt matrix and view
            // direction track the sliders live (the CustomPaint alone can't —
            // the perspective Transform is a widget-level property).
            return ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                if (controller.rendererError != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        controller.rendererError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.orangeAccent, fontSize: 13),
                      ),
                    ),
                  );
                }
                // Perspective tilt + zoom + pan of the whole painted card. The
                // relief lighting lives in the shader, so tilting + moving the
                // light makes the impasto read as real 3D. Hit-testing is
                // transformed too, so painting stays accurate at any zoom/tilt.
                final tilt = Matrix4.identity()
                  ..setEntry(3, 2, controller.perspective)
                  ..translateByDouble(controller.panX, controller.panY, 0.0, 1.0)
                  ..rotateX(controller.tiltX)
                  ..rotateY(controller.tiltY)
                  ..scaleByDouble(
                      controller.zoom, controller.zoom, controller.zoom, 1.0);
                return Transform(
                  alignment: Alignment.center,
                  transform: tilt,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF3A3A40)),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black54,
                            blurRadius: 18,
                            spreadRadius: 2),
                      ],
                    ),
                    child: Listener(
                      onPointerDown: (e) =>
                          _send(e.localPosition, size, controller.strokeStart),
                      onPointerMove: (e) {
                        if (e.buttons != 0) {
                          _send(e.localPosition, size, controller.strokeMove);
                        }
                      },
                      onPointerUp: (e) => controller.strokeEnd(),
                      onPointerCancel: (e) => controller.strokeEnd(),
                      child: ClipRect(
                        child: CustomPaint(
                          painter: ReliefPainter(
                            repaintOn: controller,
                            renderer: controller.renderer,
                            light: controller.light,
                            viewDir: controller.viewDir,
                          ),
                          size: size,
                          isComplex: true,
                          willChange: true,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ),
    );
  }
}

/// Draws a shaded relief surface via the GPU shader. Reused for both the main
/// canvas and the (flat-lit) palette by passing different renderers/lights.
class ReliefPainter extends CustomPainter {
  ReliefPainter({
    required Listenable repaintOn,
    required this.renderer,
    required this.light,
    this.viewDir = const [0.0, 0.0, 1.0],
  }) : super(repaint: repaintOn);

  final ReliefRenderer? renderer;
  final LightSettings light;
  final List<double> viewDir;

  @override
  void paint(Canvas canvas, Size size) {
    final r = renderer;
    if (r == null || !r.ready) {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF2A2A2E));
      return;
    }
    r.paint(canvas, size, light, viewDir: viewDir);
  }

  @override
  bool shouldRepaint(covariant ReliefPainter oldDelegate) => true;
}
