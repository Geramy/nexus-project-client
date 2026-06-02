// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../call_system_editor.dart';
import '../call_system_providers.dart';
import '../model/call_flow.dart';
import '../model/call_node.dart';
import 'node_visuals.dart';

/// The visual call-flow canvas: pan/zoom, draggable node cards, and edges drawn
/// between each node's output ports and its targets. Tapping a node selects it
/// (the inspector edits it). Reads the reactive [callSystemProjectProvider] and
/// writes moves/edits through [callSystemEditorProvider].
class CallFlowCanvas extends ConsumerStatefulWidget {
  const CallFlowCanvas({super.key, required this.projectId});
  final int projectId;

  @override
  ConsumerState<CallFlowCanvas> createState() => _CallFlowCanvasState();
}

class _CallFlowCanvasState extends ConsumerState<CallFlowCanvas> {
  final _transform = TransformationController();
  String? _dragId;
  Offset? _dragPos;

  double get _scale => _transform.value.getMaxScaleOnAxis();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final project = ref.watch(callSystemProjectProvider(widget.projectId));
    final flow = project.flows.isEmpty ? null : project.flows.first;
    if (flow == null) {
      return const Center(child: Text('No flow yet.'));
    }
    final selected = ref.watch(selectedCallNodeProvider(widget.projectId));
    final editor = ref.read(callSystemEditorProvider(widget.projectId));

    Offset posOf(CallNode n) =>
        (_dragId == n.id && _dragPos != null) ? _dragPos! : Offset(n.x, n.y);

    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: InteractiveViewer(
        transformationController: _transform,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(600),
        minScale: 0.4,
        maxScale: 2.0,
        child: SizedBox(
          width: 2600,
          height: 1700,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgesPainter(
                    flow: flow,
                    posOf: posOf,
                    color: scheme.outline,
                  ),
                ),
              ),
              for (final node in flow.nodes)
                Positioned(
                  left: posOf(node).dx,
                  top: posOf(node).dy,
                  child: _NodeCard(
                    node: node,
                    selected: node.id == selected,
                    onApprove: node.isProposed
                        ? () => editor.approveNode(node.id)
                        : null,
                    onReject: node.isProposed
                        ? () => editor.rejectNode(node.id)
                        : null,
                    onTap: () => ref
                        .read(selectedCallNodeProvider(widget.projectId).notifier)
                        .state = node.id,
                    onPanStart: () => setState(() {
                      _dragId = node.id;
                      _dragPos = Offset(node.x, node.y);
                    }),
                    onPanUpdate: (d) => setState(() {
                      final double s = _scale == 0 ? 1.0 : _scale;
                      _dragPos = (_dragPos ?? Offset(node.x, node.y)) + d / s;
                    }),
                    onPanEnd: () {
                      final p = _dragPos;
                      if (p != null) {
                        editor.moveNode(node.id, p.dx.clamp(0, 2600 - kNodeWidth),
                            p.dy.clamp(0, 1700 - kNodeHeight));
                      }
                      setState(() {
                        _dragId = null;
                        _dragPos = null;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.selected,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    this.onApprove,
    this.onReject,
  });

  final CallNode node;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  /// Non-null only for `proposed` (AI-generated) nodes awaiting the user's ✓.
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = colorForNodeType(node.type, scheme);
    final proposed = node.isProposed;
    final borderColor = proposed
        ? const Color(0xFFD9920B) // amber = awaiting approval
        : (selected ? color : scheme.outlineVariant);

    return GestureDetector(
      onTap: onTap,
      onPanStart: (_) => onPanStart(),
      onPanUpdate: (d) => onPanUpdate(d.delta),
      onPanEnd: (_) => onPanEnd(),
      child: Opacity(
        opacity: proposed ? 0.9 : 1,
        child: SizedBox(
          width: kNodeWidth,
          height: kNodeHeight,
          child: Material(
            elevation: selected ? 6 : 2,
            borderRadius: BorderRadius.circular(10),
            color: scheme.surface,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor,
                  width: (selected || proposed) ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(9)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(iconForNodeType(node.type), size: 20, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(node.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                            proposed
                                ? 'Proposed · review'
                                : titleForNodeType(node.type),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10.5,
                                color: proposed
                                    ? const Color(0xFFD9920B)
                                    : scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (proposed) ...[
                    _MiniBtn(
                      icon: Icons.check,
                      color: const Color(0xFF2E9E5B),
                      tooltip: 'Approve',
                      onTap: onApprove,
                    ),
                    _MiniBtn(
                      icon: Icons.close,
                      color: scheme.error,
                      tooltip: 'Reject',
                      onTap: onReject,
                    ),
                    const SizedBox(width: 4),
                  ] else
                    const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn(
      {required this.icon,
      required this.color,
      required this.tooltip,
      required this.onTap});
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Draws a curved edge from each node's bottom-center to each connected
/// target's top-center.
class _EdgesPainter extends CustomPainter {
  _EdgesPainter({required this.flow, required this.posOf, required this.color});

  final CallFlow flow;
  final Offset Function(CallNode) posOf;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = color;

    for (final node in flow.nodes) {
      final from = posOf(node);
      final start = Offset(from.dx + kNodeWidth / 2, from.dy + kNodeHeight);
      for (final target in node.outputs.values) {
        if (target == null) continue;
        final t = flow.nodeById(target);
        if (t == null) continue;
        final tp = posOf(t);
        final end = Offset(tp.dx + kNodeWidth / 2, tp.dy);
        final dy = (end.dy - start.dy).abs().clamp(40, 240) / 2;
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(start.dx, start.dy + dy, end.dx, end.dy - dy, end.dx, end.dy);
        canvas.drawPath(path, paint);
        canvas.drawCircle(end, 3, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter old) => true;
}
