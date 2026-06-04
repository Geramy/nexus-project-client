// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// End-to-end proof of the orchestrated task pipeline with a SCRIPTED (fake) LLM:
// a real worker session drives the real coordinator tools against the real DB +
// git engine on an isolated task tree — it writes a file, calls git_commit
// (which snapshots the isolated tree onto the task branch), and submits. We then
// run the deterministic merge to main and confirm the produced code is on main
// and the task reached Done. Proves "task → agent writes code → commit →
// submit → merge → Done" without burning real inference.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/features/projects/agent_assignment.dart';
import 'package:nexus_projects_client/features/projects/coordinator_session.dart';
import 'package:nexus_projects_client/features/projects/task_workflow.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
import 'package:nexus_projects_client/infrastructure/inference/inference_backend.dart';
import 'package:nexus_projects_client/infrastructure/workspace/async_lock.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/nxtprj_git_engine.dart';
import 'package:nexus_projects_client/infrastructure/workspace/vhd_workspace.dart';

/// A fake backend that replays a fixed script of tool-call rounds — one per
/// `streamChatCompletion` call — then finishes with plain content.
class ScriptedBackend extends InferenceBackend {
  ScriptedBackend(this._rounds);
  final List<List<ToolCall>> _rounds;
  int _i = 0;

  @override
  String get serverId => 'fake';
  @override
  String get name => 'Fake';
  @override
  String get implementationType => 'fake';

  @override
  Stream<ChatStreamEvent> streamChatCompletion({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    double? topP,
    int? topK,
    double? repeatPenalty,
    int? maxTokens,
    int? maxCompletionTokens,
    bool? enableThinking,
    Map<String, dynamic>? extra,
  }) async* {
    final calls = _i < _rounds.length ? _rounds[_i] : const <ToolCall>[];
    _i++;
    yield ChatStreamFinish(
      finishReason: calls.isEmpty ? 'stop' : 'tool_calls',
      toolCalls: calls,
      contentSoFar: calls.isEmpty ? 'Done.' : '',
    );
  }

  @override
  Future<ChatCompletionResponse> createChatCompletion({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    double? topP,
    int? topK,
    double? repeatPenalty,
    int? maxTokens,
    int? maxCompletionTokens,
    bool? enableThinking,
    Map<String, dynamic>? extra,
  }) async {
    final calls = _i < _rounds.length ? _rounds[_i] : const <ToolCall>[];
    _i++;
    return ChatCompletionResponse(id: 'x', choices: [
      Choice(
        index: 0,
        message: Message(role: 'assistant', content: '', toolCalls: calls),
        finishReason: calls.isEmpty ? 'stop' : 'tool_calls',
      ),
    ]);
  }

  @override
  Future<List<ModelInfo>> listModels({bool showAll = false}) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

ToolCall _tc(String id, String name, Map<String, dynamic> args) => ToolCall(
      id: id,
      type: 'function',
      function: FunctionCall(name: name, arguments: jsonEncode(args)),
    );

void main() {
  test(
      'scripted worker writes code, commits to its branch, submits; merge lands it on main and the task is Done',
      () async {
    final db = NexusDatabase.forTesting(NativeDatabase.memory());
    final dir = await Directory.systemTemp.createTemp('nx-pipeline');
    final ws = await VhdWorkspace.open('${dir.path}/project.nxtprj');
    final git = await NxtprjGitEngine.open(ws);
    final lane = AsyncLock();
    addTearDown(() async {
      git.dispose();
      ws.dispose();
      await db.close();
      await dir.delete(recursive: true);
    });

    // ── Seed: client (+ default agents), project, a worker-assigned task. ──
    final clientId =
        await db.createClientWithDefaults(name: 'Test', isDefault: true);
    final projectId = await db.createProject(
      ProjectsCompanion.insert(
        client_fk: clientId,
        name: 'Demo',
        projectType: const Value('application-development'),
      ),
    );
    final workerPk = await resolveDefaultWorkerPersonaId(db, projectId);
    expect(workerPk, isNotNull, reason: 'default worker persona must seed');
    final taskId = await db.createTaskInProject(
      projectPk: projectId,
      title: 'Add a greeting function',
      description: 'Create lib/greeting.dart with a hello() function.',
      agentPk: workerPk,
    );

    // ── Git: scaffold main, branch the task off it, hydrate an isolated tree. ──
    await ws.writeString('/README.md', '# Demo');
    await git.commitAll(message: 'chore: scaffold');
    final branch = 'task/$taskId';
    final tree = await VhdWorkspace.open('${dir.path}/task.nxtprj');
    addTearDown(() => tree.dispose());
    await git.createBranchAt(branch, base: 'main');
    await git.materializeInto(branch, tree);

    // ── The scripted "worker": write a file, commit it, then submit. ──
    final backend = ScriptedBackend([
      [
        _tc('1', 'write_file', {
          'path': '/lib/greeting.dart',
          'content': 'String hello() => "hi";\n',
        }),
        _tc('2', 'git_commit', {'message': 'feat: greeting()'}),
      ],
      [
        _tc('3', 'submit_for_completion', {
          'task_id': taskId,
          'summary': 'Added hello() in lib/greeting.dart',
          'evidence': 'committed to $branch',
        }),
      ],
    ]);

    final session = ProjectCoordinatorSession(
      client: backend,
      projectId: projectId,
      projectName: 'Worker',
      db: db,
      workspace: tree,
      git: git,
      workBranch: branch,
      gitLane: lane,
      leanTools: false,
      confirmAsk: (_, _) async => true,
      agentName: 'Worker',
    );

    await db.markTaskRunning(taskId, workerSessionPk: 0, workBranch: branch);
    // One turn is enough: the session loops its internal tool rounds.
    await for (final _ in session.runTurn('Implement the task.')) {}

    // ── The agent produced code on its ISOLATED tree and committed it. ──
    expect(await tree.exists('/lib/greeting.dart'), isTrue);
    final fresh = await db.getTaskById(taskId);
    expect(fresh!.executionStatus, TaskExecStatus.submitted,
        reason: 'worker submitted for review');

    // The commit really landed on the task branch (and NOT yet on main).
    final onBranch = await VhdWorkspace.open('${dir.path}/check.nxtprj');
    addTearDown(() => onBranch.dispose());
    await git.materializeInto(branch, onBranch);
    expect(await onBranch.exists('/lib/greeting.dart'), isTrue);

    final mainBefore = await VhdWorkspace.open('${dir.path}/main0.nxtprj');
    addTearDown(() => mainBefore.dispose());
    await git.materializeInto('main', mainBefore);
    expect(await mainBefore.exists('/lib/greeting.dart'), isFalse,
        reason: 'work is on the task branch, not main, until merge');

    // ── Merge stage (deterministic): branch → main, approve the task. ──
    await git.checkoutBranch('main');
    final merge = await git.merge(branch);
    expect(merge.outcome, isNot(MergeOutcome.conflicts));
    await db.approveTask(taskId);

    // ── The produced code is now on main and the task is Done. ──
    final mainAfter = await VhdWorkspace.open('${dir.path}/main1.nxtprj');
    addTearDown(() => mainAfter.dispose());
    await git.materializeInto('main', mainAfter);
    expect(await mainAfter.readString('/lib/greeting.dart'),
        'String hello() => "hi";\n');
    final done = await db.getTaskById(taskId);
    expect(done!.status, TaskStatus.done);
    expect(done.executionStatus, TaskExecStatus.done);
  });
}
