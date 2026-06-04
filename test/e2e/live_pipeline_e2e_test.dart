// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// LIVE end-to-end proof against the REAL Nexus Router gateway + REAL inference.
// Gated on the NEXUS_EMAIL / NEXUS_PASSWORD env vars (GitHub secrets), so it
// SKIPS in normal/local runs and only executes when credentials are provided.
//
// It proves the whole chain with a real account + real AI:
//   1. login  → mints a token WITH device_id + app_name (the routed server
//      rejects tokens minted without them — this is the regression guard);
//   2. the token actually authorizes inference (listModels: was a 401 before);
//   3. a real worker agent writes a known file, commits it to its task branch,
//      and submits — using the real session + tools + git engine;
//   4. the branch merges to main;
//   5. the produced files are EXPORTED to disk, the expected file is present,
//      and the exported Dart code COMPILES (dart analyze, no errors).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/features/projects/agent_assignment.dart';
import 'package:nexus_projects_client/features/projects/coordinator_session.dart';
import 'package:nexus_projects_client/features/projects/task_workflow.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
import 'package:nexus_projects_client/infrastructure/inference/inference_backend_factory.dart';
import 'package:nexus_projects_client/infrastructure/models/ui/inference_server.dart'
    as ui_model;
import 'package:nexus_projects_client/infrastructure/nexus/nexus_account_client.dart';
import 'package:nexus_projects_client/infrastructure/workspace/async_lock.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/nxtprj_git_engine.dart';
import 'package:nexus_projects_client/infrastructure/workspace/vhd_workspace.dart';

import 'support/model_picker.dart';

void main() {
  final email = Platform.environment['NEXUS_EMAIL'];
  final password = Platform.environment['NEXUS_PASSWORD'];
  // The workflow always sets NEXUS_GATEWAY (to the secret, which may be empty),
  // so treat an EMPTY value as "use the default" — env[..] is '' not null here.
  final gatewayEnv = Platform.environment['NEXUS_GATEWAY'];
  final gateway = (gatewayEnv == null || gatewayEnv.trim().isEmpty)
      ? 'https://api.nexus-projects.ai'
      : gatewayEnv.trim();
  final skip =
      (email == null || email.isEmpty || password == null || password.isEmpty)
      ? 'live E2E skipped: set NEXUS_EMAIL and NEXUS_PASSWORD (GitHub secrets) to run'
      : false;

  test(
    'LIVE: login → real agent writes code → commit → merge → export → compiles',
    () async {
      // ── 1. Real login. Proves the mint-token fix (device_id + app_name). ──
      final acct = NexusAccountClient(baseUrl: gateway);
      final auth = await acct.login(
        email: email!,
        password: password!,
        deviceId: 'ci-e2e-device',
        deviceName: 'github-ci',
        appName: kNexusAppName,
      );
      expect(auth.token, isNotEmpty, reason: 'login must mint a token');

      // ── 2. The token actually authorizes inference (was 401 before the fix). ──
      final server = ui_model.InferenceServer(
        id: 'routed',
        name: 'Nexus Router',
        baseUrl: gateway,
        apiKey: auth.token,
        providerType: 'routed',
      );
      final backend = backendForServer(server, agentName: 'E2E');
      final models = await backend.listModels(showAll: false);
      expect(
        models,
        isNotEmpty,
        reason: '/models must authorize with the token',
      );
      // Pick a TEXT/chat model: prefer an explicit NEXUS_MODEL, else skip
      // image/audio models (e.g. SD-Turbo) and favor known LLM families.
      final model = pickTextModel(
        models.map((m) => m.id).toList(),
        Platform.environment['NEXUS_MODEL'],
      );
      expect(model, isNotEmpty, reason: 'no text/chat model available');

      // ── 3. Seed an in-memory project + a worker task; open real git workspace. ──
      final db = NexusDatabase.forTesting(NativeDatabase.memory());
      final dir = await Directory.systemTemp.createTemp('nx-e2e');
      final ws = await VhdWorkspace.open('${dir.path}/project.nxtprj');
      final git = await NxtprjGitEngine.open(ws);
      final tree = await VhdWorkspace.open('${dir.path}/task.nxtprj');
      final lane = AsyncLock();
      addTearDown(() async {
        git.dispose();
        ws.dispose();
        tree.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });

      final clientId = await db.createClientWithDefaults(
        name: 'E2E',
        isDefault: true,
      );
      final projectId = await db.createProject(
        ProjectsCompanion.insert(
          client_fk: clientId,
          name: 'E2E Demo',
          projectType: const Value('application-development'),
        ),
      );
      final workerPk = await resolveDefaultWorkerPersonaId(db, projectId);
      final taskId = await db.createTaskInProject(
        projectPk: projectId,
        title: 'Create lib/hello.dart',
        description: 'Create lib/hello.dart with `String hello() => "hi";`.',
        agentPk: workerPk,
      );

      await ws.writeString('/README.md', '# E2E');
      await git.commitAll(message: 'chore: scaffold');
      final branch = 'task/$taskId';
      await git.createBranchAt(branch, base: 'main');
      await git.materializeInto(branch, tree);

      // ── 4. A REAL agent does the work: write the file, commit, submit. ──
      final session = ProjectCoordinatorSession(
        client: backend,
        model: model,
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
        systemPromptOverride:
            'You are an autonomous software engineer working on task #$taskId on '
            'your own branch. Do EXACTLY this and nothing else:\n'
            '1. Call write_file with path "/lib/hello.dart" and content '
            '`String hello() => "hi";\\n`.\n'
            '2. Call git_commit with a short message.\n'
            '3. Call submit_for_completion with task_id=$taskId and a one-line '
            'summary.\n'
            'Use the tools — do not just describe the steps.',
      );

      await db.markTaskRunning(taskId, workerSessionPk: 0, workBranch: branch);
      for (var turn = 0; turn < 8; turn++) {
        await for (final _ in session.runTurn('Do the task now.')) {}
        final t = await db.getTaskById(taskId);
        if (t?.executionStatus == TaskExecStatus.submitted) break;
      }
      final submitted = await db.getTaskById(taskId);
      expect(
        submitted!.executionStatus,
        TaskExecStatus.submitted,
        reason: 'the real agent should write the file, commit, and submit',
      );
      expect(await tree.exists('/lib/hello.dart'), isTrue);

      // ── 5. Merge to main + approve (deterministic stage). ──
      await git.checkoutBranch('main');
      final merge = await git.merge(branch);
      expect(merge.outcome, isNot(MergeOutcome.conflicts));
      await db.approveTask(taskId);
      expect((await db.getTaskById(taskId))!.status, TaskStatus.done);

      // ── 6. EXPORT main to disk, verify the expected file, COMPILE it. ──
      final exportDir = Directory('${dir.path}/export')..createSync();
      final mainTree = await VhdWorkspace.open('${dir.path}/main.nxtprj');
      addTearDown(() => mainTree.dispose());
      await git.materializeInto('main', mainTree);
      for (final e in await mainTree.walk()) {
        if (e.isDirectory) continue;
        final out = File('${exportDir.path}${e.path}');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(await mainTree.readBytes(e.path));
      }
      // Expected file present with the expected content.
      final hello = File('${exportDir.path}/lib/hello.dart');
      expect(
        hello.existsSync(),
        isTrue,
        reason: 'lib/hello.dart must be exported',
      );
      expect(hello.readAsStringSync(), contains('String hello()'));

      // Make it an analyzable package, then compile-check (no errors).
      File('${exportDir.path}/pubspec.yaml').writeAsStringSync(
        'name: e2e_export\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );
      final analyze = await Process.run('dart', ['analyze', exportDir.path]);
      expect(
        analyze.exitCode,
        lessThan(2),
        reason:
            'exported code must compile (analyze):\n${analyze.stdout}\n${analyze.stderr}',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
