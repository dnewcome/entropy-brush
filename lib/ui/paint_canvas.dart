import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../paint_controller.dart';
import '../render/relief_renderer.dart';
import 'orbit_gizmo.dart';
import 'slab_painter.dart';
import 'slab_view.dart';

/// The painting surface — a 3D canvas slab. Pan moves the whole slab, zoom
/// scales it, tilt rotates it (showing its thick edges). Pointer input is
/// inverse-projected onto the top face so painting lands where you click.
class PaintCanvas extends StatelessWidget {
  const PaintCanvas({super.key, required this.controller});

  final PaintController controller;

  SlabView _slab(Size size) => SlabView(
        viewW: size.width,
        viewH: size.height,
        tiltX: controller.tiltX,
        tiltY: controller.tiltY,
        roll: controller.displayRoll,
        zoom: controller.zoom,
        panX: controller.panX,
        panY: controller.panY,
        thickness: controller.canvasThicknessFrac,
      );

  void _send(Offset local, Size size, void Function(double, double) fn) {
    final c = _slab(size).screenToCanvas(local.dx, local.dy);
    if (c.x < 0 || c.x > 1 || c.y < 0 || c.y > 1) return; // missed the canvas
    final gx = (c.x * controller.grid.width).clamp(0.0, controller.grid.width - 1.0);
    final gy =
        (c.y * controller.grid.height).clamp(0.0, controller.grid.height - 1.0);
    fn(gx, gy);
  }

  /// Scroll-wheel zoom, anchored on the cursor: the canvas point under the
  /// pointer stays put (pan is additive in screen space, so this is exact).
  void _zoomAt(Offset local, Size size, double scrollDy) {
    final before = _slab(size).screenToCanvas(local.dx, local.dy);
    controller.zoom =
        (controller.zoom * math.exp(-scrollDy * 0.0015)).clamp(0.5, 12.0);
    final after = _slab(size).project(before.x, before.y, 0);
    final double s = 0.42 * (size.width < size.height ? size.width : size.height);
    controller.panX += (local.dx - after.x) / s;
    controller.panY += (local.dy - after.y) / s;
    controller.viewChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
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
              return Stack(
                children: [
                  Positioned.fill(
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
                      onPointerSignal: (e) {
                        if (e is PointerScrollEvent) {
                          _zoomAt(e.localPosition, size, e.scrollDelta.dy);
                        }
                      },
                      child: CustomPaint(
                        painter: SlabPainter(
                            repaintOn: controller, controller: controller),
                        size: size,
                        isComplex: true,
                        willChange: true,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        OrbitGizmo(controller: controller),
                        const SizedBox(height: 8),
                        ZoomControl(controller: controller),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
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
