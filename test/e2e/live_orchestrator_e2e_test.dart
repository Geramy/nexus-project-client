// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// LIVE, start-to-end proof of a whole PROJECT against the REAL Nexus Router
// gateway + REAL inference, driven by the REAL ProjectOrchestrator.
//
// Unlike live_pipeline_e2e_test.dart (one file, hand-driven), this boots the
// actual orchestrator object — its slot-pool dispatcher, weighted scheduler,
// per-task isolated working trees, the real worker AND verifier agents, and the
// deterministic auto-merge — and lets it run a small project to completion with
// up to N agents in parallel.
//
// The project is specified the way the user asked for: each task names an EXACT
// folder + file it must produce. After the orchestrator drives every task to
// Done, we export `main` and assert each named deliverable is present AND has
// real content (a minimum byte size), printing a path → bytes table to the CI
// log so the produced project is visible.
//
// Gated on NEXUS_EMAIL / NEXUS_PASSWORD (GitHub secrets): SKIPS locally, runs in
// CI. Each run spends real inference tokens across several parallel agents.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/projects/agent_assignment.dart';
import 'package:nexus_projects_client/features/projects/orchestration/project_orchestrator.dart';
import 'package:nexus_projects_client/features/projects/task_workflow.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
import 'package:nexus_projects_client/infrastructure/inference/inference_backend_factory.dart';
import 'package:nexus_projects_client/infrastructure/inference/routed_server.dart';
import 'package:nexus_projects_client/infrastructure/models/ui/inference_server.dart'
    as ui_model;
import 'package:nexus_projects_client/infrastructure/nexus/nexus_account_client.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/git_engine_provider.dart';
import 'package:nexus_projects_client/infrastructure/workspace/vhd_workspace.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace_provider.dart';

import 'support/model_picker.dart';

/// Routes path_provider to a temp dir so the orchestrator's own providers build
/// their `.nxtprj` working-tree disks under it (no real app-support dir in CI).
class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.base);
  final String base;
  @override
  Future<String?> getApplicationSupportPath() async => base;
  @override
  Future<String?> getApplicationDocumentsPath() async => base;
  @override
  Future<String?> getTemporaryPath() async => base;
  @override
  Future<String?> getApplicationCachePath() async => base;
}

/// One project deliverable: the EXACT path an agent must create, a description
/// of what to put in it, and the minimum byte size we require as "real content".
class _Deliverable {
  const _Deliverable(this.path, this.spec, this.minBytes);
  final String path;
  final String spec;
  final int minBytes;
}

void main() {
  final email = Platform.environment['NEXUS_EMAIL'];
  final password = Platform.environment['NEXUS_PASSWORD'];
  final gatewayEnv = Platform.environment['NEXUS_GATEWAY'];
  final gateway = (gatewayEnv == null || gatewayEnv.trim().isEmpty)
      ? 'https://api.nexus-projects.ai'
      : gatewayEnv.trim();
  final skip =
      (email == null || email.isEmpty || password == null || password.isEmpty)
      ? 'live orchestrator E2E skipped: set NEXUS_EMAIL and NEXUS_PASSWORD '
            '(GitHub secrets) to run'
      : false;

  // The project spec: each task names an exact folder + file to produce.
  const deliverables = <_Deliverable>[
    _Deliverable(
      '/lib/math/calculator.dart',
      'a `class Calculator` with `int add(int a, int b)` and '
          '`int subtract(int a, int b)` methods',
      60,
    ),
    _Deliverable(
      '/lib/strings/greeter.dart',
      'a top-level function `String greet(String name)` that returns '
          '"Hello, <name>!"',
      40,
    ),
    _Deliverable(
      '/lib/util/numbers.dart',
      'top-level functions `bool isEven(int n)` and `int doubleIt(int n)`',
      40,
    ),
  ];

  test(
    'LIVE orchestrator: a whole project builds its specified files start→end',
    () async {
      // ── 1. Real login (mints a token with device_id + app_name). ──────────
      final acct = NexusAccountClient(baseUrl: gateway);
      final auth = await acct.login(
        email: email!,
        password: password!,
        deviceId: 'ci-e2e-orchestrator',
        deviceName: 'github-ci',
        appName: kNexusAppName,
      );
      expect(auth.token, isNotEmpty, reason: 'login must mint a token');

      // ── 2. Pick a text/chat model from the live catalog. ──────────────────
      final probe = backendForServer(
        ui_model.InferenceServer(
          id: 'routed',
          name: 'Nexus Router',
          baseUrl: gateway,
          apiKey: auth.token,
          providerType: 'routed',
        ),
        agentName: 'E2E',
      );
      final catalog = await probe.listModels(showAll: false);
      expect(catalog, isNotEmpty, reason: '/models must authorize');
      final model = pickTextModel(
        catalog.map((m) => m.id).toList(),
        Platform.environment['NEXUS_MODEL'],
      );
      expect(model, isNotEmpty, reason: 'no text/chat model available');

      // ── 3. Temp app-support dir → the orchestrator builds its own disks. ──
      final dir = await Directory.systemTemp.createTemp('nx-orch-e2e');
      PathProviderPlatform.instance = _TempPathProvider(dir.path);

      // ── 4. In-memory DB; override ONLY the database provider so the real
      //      orchestrator (and its providers) run against it. ────────────────
      final db = NexusDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [nexusDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });

      // ── 5. Seed: client (+default agent personas: worker/verifier/coord),
      //      a ROUTED inference server bound to the LIVE token, the project,
      //      and one worker task per deliverable. ──────────────────────────
      final clientId = await db.createClientWithDefaults(
        name: 'E2E',
        isDefault: true,
      );
      await db.createInferenceServer(
        InferenceServersCompanion.insert(
          client_fk: clientId,
          name: 'Nexus Router',
          baseUrl: gateway,
          apiKey: Value(auth.token),
          providerType: const Value(kRoutedProviderType),
          maxConcurrency: const Value(3), // run up to 3 agents at once
          selectedModel: Value(model),
          availableModelsJson: Value(jsonEncode([model])),
        ),
      );
      final projectId = await db.createProject(
        ProjectsCompanion.insert(
          client_fk: clientId,
          name: 'Toolkit',
          projectType: const Value('application-development'),
        ),
      );
      final workerPk = await resolveDefaultWorkerPersonaId(db, projectId);
      expect(workerPk, isNotNull, reason: 'a default worker persona must seed');

      for (final d in deliverables) {
        await db.createTaskInProject(
          projectPk: projectId,
          agentPk: workerPk,
          title: 'Create ${d.path}',
          description:
              'Create the file `${d.path}` (create any parent folders). It '
              'must contain ${d.spec}. Write real, well-formed Dart that '
              'compiles. Use write_file with the EXACT path `${d.path}`, then '
              'call git_commit, then submit_for_completion.',
        );
      }

      // ── 6. Scaffold `main` on the orchestrator's OWN shared workspace
      //      (same provider instances it will use). ─────────────────────────
      final ws = await container.read(workspaceFsProvider(projectId).future);
      final git = await container.read(gitEngineProvider(projectId).future);
      await ws.writeString('/README.md', '# Toolkit\n');
      await git.commitAll(message: 'chore: scaffold');

      // ── 7. Boot the REAL orchestrator and start it. The state change fires
      //      its watch → _pump, which fills up to 3 parallel agent slots. ────
      container.read(projectOrchestratorProvider(projectId)); // self-starts
      await db.setProjectOrchestrationState(projectId, 'running');

      // ── 8. Drive to completion: poll until every task reaches Done. ───────
      final deadline = DateTime.now().add(const Duration(minutes: 9));
      var done = 0;
      var maxConcurrentSeen = 0;
      while (DateTime.now().isBefore(deadline)) {
        final tasks = await db.getTasksForProject(projectId);
        done = tasks.where((t) => t.status == TaskStatus.done).length;
        final running = tasks
            .where((t) => t.executionStatus == TaskExecStatus.running)
            .length;
        if (running > maxConcurrentSeen) maxConcurrentSeen = running;
        if (done == deliverables.length) break;
        await Future<void>.delayed(const Duration(seconds: 4));
      }
      // Stop the orchestrator before we read/export (no concurrent git ops).
      await db.setProjectOrchestrationState(projectId, 'stopped');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // ── 9. Export `main` and verify each named deliverable has real content.
      final mainTree = await VhdWorkspace.open('${dir.path}/main-export.nxtprj');
      addTearDown(() => mainTree.dispose());
      await git.materializeInto('main', mainTree);

      final report = StringBuffer()
        ..writeln()
        ..writeln('── Project "Toolkit" output on main ──')
        ..writeln('   tasks Done: $done/${deliverables.length}   '
            'max agents seen running at once: $maxConcurrentSeen');
      for (final d in deliverables) {
        final exists = await mainTree.exists(d.path);
        final bytes = exists ? (await mainTree.readBytes(d.path)).length : 0;
        report.writeln(
          '   ${d.path.padRight(28)} → ${bytes.toString().padLeft(5)} bytes'
          '${exists ? '' : '   (MISSING)'}',
        );
      }
      debugPrint(report.toString());

      // Every task drove to Done…
      expect(
        done,
        deliverables.length,
        reason:
            'the orchestrator should drive every task to Done.\n$report',
      );
      // …and every named file exists on main with real, non-trivial content.
      for (final d in deliverables) {
        expect(
          await mainTree.exists(d.path),
          isTrue,
          reason: '${d.path} must be produced and merged to main',
        );
        final bytes = (await mainTree.readBytes(d.path)).length;
        expect(
          bytes,
          greaterThanOrEqualTo(d.minBytes),
          reason:
              '${d.path} must have real content (got $bytes bytes, '
              'expected ≥ ${d.minBytes})',
        );
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
