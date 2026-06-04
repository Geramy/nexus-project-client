// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nexus_projects_client/services/audio/audio_recorder_service.dart';

/// Live mic waveform visualizer for the voice call, modeled on lemonade_mobile's
/// LiveAudioVisualizer + recording amplitudes.
class LiveMicVisualizer extends StatefulWidget {
  final Color color;
  final double height;
  final int barCount;
  final AudioRecorderService?
  recorder; // Pass the active recorder for real levels

  const LiveMicVisualizer({
    super.key,
    this.color = Colors.blueAccent,
    this.height = 48,
    this.barCount = 20,
    this.recorder,
  });

  @override
  State<LiveMicVisualizer> createState() => _LiveMicVisualizerState();
}

class _LiveMicVisualizerState extends State<LiveMicVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _bars = [];
  Timer? _timer;
  AudioRecorderService? get _activeRecorder => widget.recorder;

  @override
  void initState() {
    super.initState();
    _bars.addAll(List.filled(widget.barCount, 0.05));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    )..repeat();

    // Poll amplitude from the active recorder (or fallback to internal one)
    final recorderToUse = _activeRecorder ?? AudioRecorderService();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!mounted) return;
      try {
        final amp = await recorderToUse.getAmplitude();
        if (mounted) {
          setState(() {
            _bars.removeAt(0);
            _bars.add(amp.clamp(0.0, 1.0));
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _MicBarPainter(bars: _bars, color: widget.color),
        );
      },
    );
  }
}

class _MicBarPainter extends CustomPainter {
  final List<double> bars;
  final Color color;

  _MicBarPainter({required this.bars, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final barCount = bars.length;
    final spacing = 2.0;
    final barWidth = (size.width - (barCount - 1) * spacing) / barCount;

    for (int i = 0; i < barCount; i++) {
      final amp = bars[i].clamp(0.03, 1.0);
      final h = amp * size.height * 0.95;
      final x = i * (barWidth + spacing);
      final y = (size.height - h) / 2;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth.clamp(2.5, 6.0), h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MicBarPainter oldDelegate) => true;
}
