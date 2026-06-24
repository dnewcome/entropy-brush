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
    // Map the pointer through the same UV zoom/pan the shader uses, so painting
    // lands where you click at any zoom.
    final double uvx = (local.dx / size.width - 0.5) / controller.zoom +
        0.5 +
        controller.panX;
    final double uvy = (local.dy / size.height - 0.5) / controller.zoom +
        0.5 +
        controller.panY;
    final double gx =
        (uvx * controller.grid.width).clamp(0.0, controller.grid.width - 1.0);
    final double gy =
        (uvy * controller.grid.height).clamp(0.0, controller.grid.height - 1.0);
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
                // Perspective tilt only (zoom + pan are done in the shader's UV
                // so the render stays crisp instead of magnifying a raster).
                final tilt = Matrix4.identity()
                  ..setEntry(3, 2, controller.perspective)
                  ..rotateX(controller.tiltX)
                  ..rotateY(controller.tiltY);
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
                            zoom: controller.zoom,
                            panX: controller.panX,
                            panY: controller.panY,
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
    this.zoom = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
  }) : super(repaint: repaintOn);

  final ReliefRenderer? renderer;
  final LightSettings light;
  final List<double> viewDir;
  final double zoom, panX, panY;

  @override
  void paint(Canvas canvas, Size size) {
    final r = renderer;
    if (r == null || !r.ready) {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF2A2A2E));
      return;
    }
    r.paint(canvas, size, light,
        viewDir: viewDir, zoom: zoom, panX: panX, panY: panY);
  }

  @override
  bool shouldRepaint(covariant ReliefPainter oldDelegate) => true;
}
