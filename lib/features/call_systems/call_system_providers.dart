// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../infrastructure/database/nexus_database.dart' show CallSystem;
import 'model/call_flow.dart';
import 'model/call_node.dart';
import 'model/call_system_project.dart';

/// Reactive stored row (null until first saved).
final callSystemRowProvider =
    StreamProvider.family<CallSystem?, int>((ref, projectId) {
  return ref.watch(nexusDatabaseProvider).watchCallSystem(projectId);
});

/// The decoded portable [CallSystemProject] for a project — the saved document,
/// or a fresh starter when nothing's been saved yet.
final callSystemProjectProvider =
    Provider.family<CallSystemProject, int>((ref, projectId) {
  final row = ref.watch(callSystemRowProvider(projectId)).valueOrNull;
  final raw = row?.json.trim() ?? '';
  if (raw.isEmpty || raw == '{}') return starterCallSystem();
  try {
    return CallSystemProject.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return starterCallSystem();
  }
});

/// Persist a [CallSystemProject] for a project (whole-document upsert).
Future<void> saveCallSystemProject(
    Ref ref, int projectId, CallSystemProject project) {
  return ref
      .read(nexusDatabaseProvider)
      .upsertCallSystem(projectId, jsonEncode(project.toJson()));
}

/// A minimal starter document: a single "Main" flow that greets the caller and
/// hangs up, plus a welcome prompt — enough for the builder to render and for
/// the user to start editing.
CallSystemProject starterCallSystem({
  String name = 'Call System',
  CallSystemSubCategory subCategory = CallSystemSubCategory.inboundIvr,
}) {
  const welcomePromptId = 'prompt_welcome';
  const entryId = 'node_entry';
  const greetId = 'node_greet';
  const hangupId = 'node_hangup';

  final flow = CallFlow(
    id: 'flow_main',
    name: 'Main',
    description: 'The entry flow for inbound calls.',
    entryNodeId: entryId,
    nodes: const [
      CallNode(
        id: entryId,
        type: CallNodeType.entry,
        label: 'Call starts',
        x: 80,
        y: 80,
        outputs: {'next': greetId},
      ),
      CallNode(
        id: greetId,
        type: CallNodeType.playPrompt,
        label: 'Greeting',
        x: 80,
        y: 220,
        config: {'promptId': welcomePromptId},
        outputs: {'next': hangupId},
      ),
      CallNode(
        id: hangupId,
        type: CallNodeType.hangup,
        label: 'End call',
        x: 80,
        y: 360,
      ),
    ],
  );

  return CallSystemProject(
    name: name,
    subCategory: subCategory,
    flows: [flow],
    prompts: const [
      Prompt(
        id: welcomePromptId,
        text: 'Thank you for calling. Please listen carefully to the following options.',
        voice: 'af_heart',
      ),
    ],
  );
}
