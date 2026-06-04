// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Accumulates indexed `delta.tool_calls[]` fragments across streaming chunks.

// The types are defined in chat_response.dart which imports tool_call.dart.
// We import from the response file so both ToolCall and PartialToolCall resolve.
import '../types/chat_message.dart'; // gives us ApiChatMessage for _map helpers if needed
import '../types/tool_call.dart' as tc;

/// Accumulates indexed `delta.tool_calls[]` fragments across streaming chunks.
class ToolCallAssembler {
  final Map<int, _Slot> _slots = {};

  /// Apply a single chunk's `delta`. Returns the partials touched by this delta.
  List<tc.PartialToolCall> observe(Map<String, dynamic> delta) {
    final raw = delta['tool_calls'];
    if (raw is! List) return const [];
    final touched = <tc.PartialToolCall>[];

    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final indexRaw = entry['index'];
      if (indexRaw is! num) continue;
      final index = indexRaw.toInt();
      final slot = _slots.putIfAbsent(index, () => _Slot(index));

      final id = entry['id'];
      if (id is String && id.isNotEmpty && slot.id == null) {
        slot.id = id;
      }

      final fn = entry['function'];
      if (fn is Map<String, dynamic>) {
        final name = fn['name'];
        if (name is String && name.isNotEmpty && slot.name == null) {
          slot.name = name;
        }
        final args = fn['arguments'];
        if (args is String && args.isNotEmpty) {
          slot.argsBuffer.write(args);
        }
      }

      touched.add(slot.toPartial());
    }

    return touched;
  }

  /// Snapshot of current accumulator state, ordered by index.
  List<tc.PartialToolCall> snapshot() {
    final keys = _slots.keys.toList()..sort();
    return [for (final k in keys) _slots[k]!.toPartial()];
  }

  /// Produce the final [tc.ToolCall] list. Slots missing id or name are dropped.
  List<tc.ToolCall> finalize() {
    final keys = _slots.keys.toList()..sort();
    final result = <tc.ToolCall>[];
    for (final k in keys) {
      final s = _slots[k]!;
      if (s.id == null || s.name == null) continue;
      final args = s.argsBuffer.toString();
      result.add(
        tc.ToolCall(
          id: s.id!,
          name: s.name!,
          argumentsJson: args.isEmpty ? '{}' : args,
        ),
      );
    }
    return result;
  }

  bool get isEmpty => _slots.isEmpty;
}

class _Slot {
  final int index;
  String? id;
  String? name;
  final StringBuffer argsBuffer = StringBuffer();
  _Slot(this.index);
  tc.PartialToolCall toPartial() => tc.PartialToolCall(
    index: index,
    id: id,
    name: name,
    argumentsAccum: argsBuffer.toString(),
  );
}
