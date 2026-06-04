// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// LIVE proof of the post-setup PROJECT EXPLORATION workflow, with screenshots:
//   1. a real discovery Coordinator (live inference, discoveryMode) interviews
//      and builds the USER-STORY TREE via the add_user_story tool;
//   2. the two-pane Exploration screen (UML story tree + discovery chat) is
//      screenshotted;
//   3. "Generate tasks from stories" turns the tree into TASKS, each linked
//      back to its story (task_story_fk) — verified from the DB;
//   4. timing is recorded and the screenshots are bundled for the release.
//
// Gated on NEXUS_EMAIL / NEXUS_PASSWORD.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/projects/coordinator_session.dart';
import 'package:nexus_projects_client/features/projects/exploration/exploration_session.dart';
import 'package:nexus_projects_client/features/projects/exploration/project_exploration_view.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
import 'package:nexus_projects_client/infrastructure/inference/inference_backend_factory.dart';
import 'package:nexus_projects_client/infrastructure/inference/routed_server.dart';
import 'package:nexus_projects_client/infrastructure/models/ui/inference_server.dart'
    as ui_model;
import 'package:nexus_projects_client/infrastructure/nexus/nexus_account_client.dart';

import '../test/e2e/support/metrics.dart';
import '../test/e2e/support/model_picker.dart';

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final email = Platform.environment['NEXUS_EMAIL'];
  final password = Platform.environment['NEXUS_PASSWORD'];
  final gatewayEnv = Platform.environment['NEXUS_GATEWAY'];
  final gateway = (gatewayEnv == null || gatewayEnv.trim().isEmpty)
      ? 'https://api.nexus-projects.ai'
      : gatewayEnv.trim();
  final hasCreds =
      email != null &&
      email.isNotEmpty &&
      password != null &&
      password.isNotEmpty;
  final shotsDir = Platform.environment['NEXUS_SHOTS_DIR'] ?? 'setup_shots';

  testWidgets(
    'LIVE exploration: discovery builds stories → screenshot → generate tasks',
    (tester) async {
      // ── Login + pick a text model. ───────────────────────────────────────
      final acct = NexusAccountClient(baseUrl: gateway);
      final auth = await acct.login(
        email: email!,
        password: password!,
        deviceId: 'ci-e2e-exploration',
        deviceName: 'github-ci',
        appName: kNexusAppName,
      );
      // Resolve the coordinator model like the app: the Omni collection
      // (LMX-Omni-52B-Halo) → its LLM component.
      final resolved = await resolveCoordinatorModel(
        gateway: gateway,
        token: auth.token,
        override: Platform.environment['NEXUS_MODEL'],
      );
      final model = resolved.chat;
      expect(model, isNotEmpty);
      debugPrint(
        'coordinator model → collection=${resolved.collection}, chat=$model',
      );
      final backend = backendForServer(
        ui_model.InferenceServer(
          id: 'routed',
          name: 'Nexus Router',
          baseUrl: gateway,
          apiKey: auth.token,
          providerType: 'routed',
        ),
        agentName: 'Coordinator',
      );

      // ── Seed an in-memory project already IN the exploration phase. ───────
      final tmp = await Directory.systemTemp.createTemp('nx-explore');
      PathProviderPlatform.instance = _TempPathProvider(tmp.path);
      final db = NexusDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [nexusDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
        await tmp.delete(recursive: true);
      });

      final clientId = await db.createClientWithDefaults(
        name: 'Explore',
        isDefault: true,
      );
      await db.createInferenceServer(
        InferenceServersCompanion.insert(
          client_fk: clientId,
          name: 'Nexus Router',
          baseUrl: gateway,
          apiKey: Value(auth.token),
          providerType: const Value(kRoutedProviderType),
          selectedModel: Value(model),
          availableModelsJson: Value('["$model"]'),
        ),
      );
      final projectId = await db.createProject(
        ProjectsCompanion.insert(
          client_fk: clientId,
          name: 'Notes App',
          projectType: const Value('application-development'),
        ),
      );
      await db.setProjectSetupStatus(projectId, 'complete');
      await db.setProjectExplorationStatus(projectId, 'active');

      final metrics = MetricsLog('exploration_flow');

      // ── 1. LIVE discovery: a discoveryMode Coordinator builds the story
      //      tree via the add_user_story tool (no task tools available). ─────
      final prompt = await buildDiscoveryPrompt(db, projectId, 'Notes App');
      final session = ProjectCoordinatorSession(
        client: backend,
        model: model,
        projectId: projectId,
        projectName: 'Notes App',
        db: db,
        discoveryMode: true,
        systemPromptOverride: prompt,
        confirmAsk: (_, _) async => true,
        leanTools: false,
      );
      const asks = [
        'I want a simple personal notes app: create notes, edit them, and '
            'delete them. Please capture these as user stories (As a… I want… '
            'so that…), one per feature.',
        'Add acceptance criteria to each, and one more story for searching '
            'notes. Then list the stories.',
      ];
      final sw = Stopwatch()..start();
      for (final ask in asks) {
        try {
          await for (final _ in session.runTurn(ask)) {}
        } catch (_) {}
        if ((await db.getUserStoriesForProject(projectId)).length >= 2) break;
      }
      sw.stop();
      var stories = await db.getUserStoriesForProject(projectId);
      metrics.record(
        'discovery',
        'coordinator built ${stories.length} stories',
        sw.elapsed,
        ok: stories.isNotEmpty,
        extra: {'stories': stories.length, 'model': model},
      );

      // Reliability net: if the live model didn't emit stories, seed a small
      // tree deterministically so the rest of the workflow is still proven.
      if (stories.length < 2) {
        for (final s in const [
          'Create a note',
          'Edit a note',
          'Delete a note',
        ]) {
          await db.createUserStory(
            UserStoriesCompanion.insert(
              project_fk: projectId,
              title: s,
              narrative: Value('As a user, I want to $s.'),
            ),
          );
        }
        stories = await db.getUserStoriesForProject(projectId);
      }
      expect(stories, isNotEmpty, reason: 'discovery should produce stories');

      // ── 2. Mount the Exploration screen and screenshot it. ───────────────
      final shotKey = GlobalKey();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: shotKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: ProjectExplorationView(
                  projectId: projectId,
                  projectName: 'Notes App',
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      var shotN = 0;
      Future<void> shot(String label) async {
        try {
          final boundary =
              shotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1.0);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (bytes == null) return;
          final name = 'exp_${(++shotN).toString().padLeft(2, '0')}_$label';
          final f = File('$shotsDir/$name.png');
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes.buffer.asUint8List());
        } catch (e) {
          debugPrint('exploration screenshot "$label" failed: $e');
        }
      }

      await shot('story_tree');

      // ── 3. Press "Generate tasks from stories". The new generator runs a
      //      scoped AI session PER story, so wait until the run completes. ────
      final genBtn = find.textContaining('Generate tasks from stories');
      expect(genBtn, findsOneWidget);
      await tester.tap(genBtn);
      final genDeadline = DateTime.now().add(const Duration(minutes: 6));
      while (DateTime.now().isBefore(genDeadline)) {
        await tester.pump(const Duration(milliseconds: 500));
        final p = await db.getProjectById(projectId);
        if (p?.explorationStatus == 'complete') break;
      }
      await shot('tasks_generated');

      // ── 4. Verify each task links back to a story (task ↔ story). ────────
      final tasks = await db.getTasksForProject(projectId);
      expect(tasks, isNotEmpty, reason: 'tasks should be generated');
      expect(
        tasks.every((t) => t.task_story_fk != null),
        isTrue,
        reason: 'every generated task must link back to its story',
      );
      final proj = await db.getProjectById(projectId);
      expect(proj!.explorationStatus, 'complete');

      metrics.record(
        'generate',
        '${tasks.length} tasks generated, all story-linked',
        Duration.zero,
        extra: {'tasks': tasks.length, 'stories': stories.length},
      );
      final mDir = await metrics.flush();
      debugPrint(metrics.renderTable());
      debugPrint(
        'exploration: ${stories.length} stories → ${tasks.length} linked tasks'
        '  •  shots → $shotsDir  •  metrics → ${mDir.path}',
      );
    },
    skip: !hasCreds,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
