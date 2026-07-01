import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'paint_controller.dart';
import 'ui/control_panel.dart';
import 'ui/paint_canvas.dart';

void main() {
  runApp(const EntropyBrushApp());
}

class EntropyBrushApp extends StatelessWidget {
  const EntropyBrushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'entropy-brush',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A1D),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final PaintController controller;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    controller = PaintController();
    _ticker = createTicker((_) => controller.frame());
    _ticker.start();
    _init();
  }

  Future<void> _init() async {
    await controller.attachRenderer();
    // Start with pigment A loaded so the first stroke paints.
    controller.setPigment(0.12, 0.20, 0.62);
    controller.reloadBrush();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide screens (desktop / web / tablet-landscape) show the controls as a
        // fixed sidebar. Narrow screens (phones) tuck them into a slide-out
        // drawer so the canvas gets the whole screen.
        final bool wide = constraints.maxWidth >= 720;
        if (wide) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: PaintCanvas(controller: controller),
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: ControlPanel(controller: controller),
                  ),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          endDrawer: Drawer(
            width: math.min(340, constraints.maxWidth * 0.86),
            backgroundColor: const Color(0xFF1A1A1D),
            child: SafeArea(child: ControlPanel(controller: controller)),
          ),
          body: SafeArea(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: PaintCanvas(controller: controller),
                ),
                // A pull-tab on the right edge signals the controls drawer and
                // opens it on tap (edge-swipe still works too).
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Builder(
                      builder: (context) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Scaffold.of(context).openEndDrawer(),
                        child: Container(
                          width: 22,
                          height: 80,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xE61C1C20),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(11),
                              bottomLeft: Radius.circular(11),
                            ),
                            border: Border(
                              top: BorderSide(color: Color(0xFF55555C)),
                              left: BorderSide(color: Color(0xFF55555C)),
                              bottom: BorderSide(color: Color(0xFF55555C)),
                            ),
                          ),
                          child: const Icon(Icons.chevron_left,
                              size: 20, color: Color(0xFFBBBBC4)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
