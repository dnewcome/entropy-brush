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
}
