// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// LIVE, full-UI walkthrough of the PROJECT SETUP interview against the real
// gateway + real inference, driven through the actual setup wizard widgets.
//
// It navigates the real UI the way a user would — taps "Start setup", types
// into the real composer, taps Send, advances through the AI host's questions,
// then Finalizes — and at every step it:
//   * SCREENSHOTS the UI (PNG, via RepaintBoundary) → NEXUS_SHOTS_DIR;
//   * TIMES the turn (how long the host took to answer) and logs "Q → A";
//   * writes machine-readable timing (jsonl + csv) → NEXUS_METRICS_DIR, plus a
//     human transcript.txt, so CI can collect statistics over time and bundle
//     the screenshots into each release.
//
// Uses the integration_test binding but runs headless under `flutter test`
// (no desktop window / driver needed); screenshots are captured by rasterizing
// the wizard's RepaintBoundary. Gated on NEXUS_EMAIL / NEXUS_PASSWORD.

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
import 'package:nexus_projects_client/features/project_setup/project_setup_wizard.dart';
import 'package:nexus_projects_client/features/project_setup/setup_chat_controller.dart';
import 'package:nexus_projects_client/features/project_setup/setup_interview_panel.dart';
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
  // testWidgets.skip is a bool (no reason string); gate on creds being present.
  final hasCreds =
      email != null &&
      email.isNotEmpty &&
      password != null &&
      password.isNotEmpty;

  final shotsDir = Platform.environment['NEXUS_SHOTS_DIR'] ?? 'screenshots';

  // Walk the setup ONE STAGE AT A TIME: each message targets a single topic so
  // the host proposes that category's tags, and we screenshot + count after
  // each. (key = the tag category the stage should populate.) The stack
  // categories (languages/frameworks) are NOT asked — they're derived by the
  // deterministic "Resolve stack" step after the intent stages.
  const stages = <({String key, String message})>[
    (
      key: 'industries',
      message:
          'Let\'s set up a new app. It is a personal productivity to-do / task '
          'tracker for general consumer use (not a regulated industry).',
    ),
    (
      key: 'platforms',
      message:
          'It must run on these platforms: iOS, Android, and the Web.',
    ),
    (
      key: 'objectives',
      message:
          'Objectives: a customer-facing UI, works offline, and syncs data '
          'when online.',
    ),
    (
      key: 'features',
      message:
          'Features it must ship: create and edit tasks, mark complete, set '
          'due dates, and local reminders/notifications.',
    ),
    (
      key: 'databases',
      message:
          'For data storage: keep tasks and user data in a local SQLite '
          'database on-device, and a PostgreSQL database on the server for '
          'sync. Please capture those as database tags.',
    ),
    (
      key: 'services',
      message:
          'External services: push notifications for reminders, and email for '
          'account verification. No payments.',
    ),
  ];

  testWidgets(
    'LIVE setup interview: navigate the real UI, screenshot + time each step',
    (tester) async {
      // ── Login (live) → routed token, then pick a text model. ─────────────
      final acct = NexusAccountClient(baseUrl: gateway);
      final auth = await acct.login(
        email: email!,
        password: password!,
        deviceId: 'ci-e2e-setup-ui',
        deviceName: 'github-ci',
        appName: kNexusAppName,
      );
      expect(auth.token, isNotEmpty);
      final probe = backendForServer(
        ui_model.InferenceServer(
          id: 'routed',
          name: 'Nexus Router',
          baseUrl: gateway,
          apiKey: auth.token,
          providerType: 'routed',
        ),
        agentName: 'SetupUI',
      );
      final model = pickTextModel(
        (await probe.listModels(showAll: false)).map((m) => m.id).toList(),
        Platform.environment['NEXUS_MODEL'],
      );
      expect(model, isNotEmpty);

      // ── Temp app-support dir (plan files) + in-memory DB. ────────────────
      final tmp = await Directory.systemTemp.createTemp('nx-setup-ui');
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
        name: 'Setup UI',
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
          name: 'Tasks App',
          projectType: const Value('application-development'),
        ),
      );

      // ── Mount the REAL wizard inside a RepaintBoundary we can rasterize. ──
      final shotKey = GlobalKey();
      tester.view.physicalSize = const Size(1280, 840);
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
              home: ProjectSetupWizard(
                projectId: projectId,
                clientId: clientId,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final controller = container.read(
        setupChatControllerProvider((projectId: projectId, clientId: clientId)),
      );
      final metrics = MetricsLog('setup_flow');
      final transcript = StringBuffer('Project setup interview transcript\n');
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
          final name = '${(++shotN).toString().padLeft(2, '0')}_$label';
          final file = File('$shotsDir/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes.buffer.asUint8List());
        } catch (e) {
          debugPrint('screenshot "$label" failed: $e');
        }
      }

      // Pump real frames until the host turn settles. CRITICAL: the host's
      // `ask_question` tool leaves the turn `busy` while it AWAITS the user's
      // answer, so we must also stop the moment a question is pending (else we'd
      // block the whole timeout). Returns on: idle, pending question, or cap.
      Future<void> waitTurn(int maxSeconds) async {
        final end = DateTime.now().add(Duration(seconds: maxSeconds));
        while (DateTime.now().isBefore(end)) {
          if (!controller.busy || controller.pendingQuestion != null) return;
          await tester.pump(const Duration(milliseconds: 250));
        }
      }

      // Bounded settle that never hangs on a perpetual animation (busy spinner).
      Future<void> settle([int ms = 600]) async {
        await tester.pump(const Duration(milliseconds: 80));
        await tester.pump(Duration(milliseconds: ms));
      }

      String latestHostText() {
        for (final m in controller.messages.reversed) {
          if (m.kind == SetupMsgKind.question ||
              m.kind == SetupMsgKind.assistant) {
            return m.text;
          }
        }
        return '(no host message yet)';
      }

      String snip(String s) {
        final one = s.replaceAll('\n', ' ').trim();
        return one.length > 70 ? '${one.substring(0, 70)}…' : one;
      }

      // ── Step 1: Overview screen. ─────────────────────────────────────────
      await shot('overview');
      expect(find.text('Start setup'), findsOneWidget);
      await tester.tap(find.text('Start setup'));
      await settle();
      await shot('interview_start');

      final composer = find
          .descendant(
            of: find.byType(SetupInterviewPanel),
            matching: find.byType(TextField),
          )
          .first;

      // Snapshot the tag board straight from the DB: category → non-rejected
      // values. This is how we VERIFY each stage actually produced tags.
      Future<Map<String, List<String>>> tagsByCategory() async {
        final rows = await db.getTagsForProject(projectId);
        final byCat = <String, List<String>>{};
        for (final r in rows) {
          if (r.status == 'rejected') continue;
          (byCat[r.category] ??= <String>[]).add(r.value);
        }
        return byCat;
      }

      // Send one message through the real composer + wait for the host to settle.
      Future<bool> sendMessage(String text) async {
        await waitTurn(150);
        final send = find.byIcon(Icons.send);
        if (send.evaluate().isEmpty) return false; // composer busy / no button
        await tester.enterText(composer, text);
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(send);
        await tester.pump(const Duration(milliseconds: 120));
        await waitTurn(120);
        return true;
      }

      // ── Walk each setup STAGE one at a time; screenshot + count tags after. ─
      final interviewBudget = DateTime.now().add(const Duration(minutes: 8));
      var stagesRun = 0;
      for (
        var i = 0;
        i < stages.length &&
            !controller.refining &&
            DateTime.now().isBefore(interviewBudget);
        i++
      ) {
        final stage = stages[i];
        final sw = Stopwatch()..start();
        await sendMessage(stage.message);
        sw.stop();
        stagesRun++;

        final byCat = await tagsByCategory();
        final count = byCat[stage.key]?.length ?? 0;
        metrics.record(
          'stage',
          '${i + 1}. ${stage.key} ($count tags)',
          sw.elapsed,
          ok: count > 0,
          extra: {
            'stage': stage.key,
            'tags': count,
            'turn': i + 1,
            'model': model,
          },
        );
        transcript
          ..writeln(
            '\n── stage ${i + 1}: ${stage.key}  '
            '(${sw.elapsed.inMilliseconds} ms → $count tags) ──',
          )
          ..writeln('User: ${stage.message}')
          ..writeln('Host: ${snip(latestHostText())}')
          ..writeln('Tags now: ${(byCat[stage.key] ?? const []).join(', ')}');

        await settle(300);
        await shot('stage_${(i + 1).toString().padLeft(2, '0')}_${stage.key}');
      }

      // ── Resolve the stack (DETERMINISTIC): derives languages + frameworks
      //    (Client↔Server↔DB) from the platforms/objectives the host captured.
      //    This is the step the earlier test skipped — why the stack was empty.
      final resolveBtn = find.text('Resolve stack');
      if (resolveBtn.evaluate().isNotEmpty) {
        final sw = Stopwatch()..start();
        try {
          await tester.ensureVisible(resolveBtn);
        } catch (_) {}
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(resolveBtn);
        // Wait for the resolver's async upserts to land language+framework tags.
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(end)) {
          final byCat = await tagsByCategory();
          if ((byCat['languages']?.isNotEmpty ?? false) &&
              (byCat['frameworks']?.isNotEmpty ?? false)) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 300));
        }
        sw.stop();
        final byCat = await tagsByCategory();
        metrics.record(
          'resolve_stack',
          'derive languages + frameworks',
          sw.elapsed,
          ok: (byCat['languages']?.isNotEmpty ?? false),
          extra: {
            'languages': byCat['languages']?.length ?? 0,
            'frameworks': byCat['frameworks']?.length ?? 0,
            'model': model,
          },
        );
        transcript.writeln(
          '\n── resolve stack (${sw.elapsed.inMilliseconds} ms) → '
          'languages=${byCat['languages']?.length ?? 0}, '
          'frameworks=${byCat['frameworks']?.length ?? 0} ──',
        );
      } else {
        transcript.writeln('\n── "Resolve stack" button not found ──');
      }
      await settle(400);
      await shot('stack_resolved');

      // ── Finalize → generate plans (best-effort). ─────────────────────────
      if (!controller.refining) {
        final fin = find.text('Finalize & generate plans');
        if (fin.evaluate().isNotEmpty) {
          final sw = Stopwatch()..start();
          try {
            await tester.ensureVisible(fin);
          } catch (_) {}
          await tester.tap(fin);
          await tester.pump(const Duration(milliseconds: 150));
          final end = DateTime.now().add(const Duration(seconds: 90));
          while (controller.busy && DateTime.now().isBefore(end)) {
            await tester.pump(const Duration(milliseconds: 300));
          }
          sw.stop();
          metrics.record(
            'phase',
            'finalize → generate plans',
            sw.elapsed,
            ok: controller.refining,
            extra: {'model': model},
          );
          transcript.writeln(
            '\n── finalize (${sw.elapsed.inMilliseconds} ms) → '
            'refining=${controller.refining} ──',
          );
        }
      }
      await settle(400);
      await shot('finalize');

      // ── Verify EACH required category actually has tags. ─────────────────
      const allCats = [
        'industries',
        'platforms',
        'objectives',
        'features',
        'languages',
        'frameworks',
        'databases',
        'libraries',
        'services',
      ];
      final finalTags = await tagsByCategory();
      final table = StringBuffer()..writeln('\n── Tag board by category ──');
      for (final cat in allCats) {
        final vals = finalTags[cat] ?? const [];
        table.writeln(
          '   ${cat.padRight(12)} ${vals.length.toString().padLeft(2)}  '
          '${vals.take(6).join(', ')}',
        );
      }
      metrics.record(
        'tags',
        'final tag board by category',
        Duration.zero,
        extra: {
          for (final cat in allCats) cat: finalTags[cat]?.length ?? 0,
          'model': model,
        },
      );

      // ── Persist timing + transcript + tag table. ─────────────────────────
      final mDir = await metrics.flush();
      await File(
        '$shotsDir/transcript.txt',
      ).writeAsString('$transcript\n$table');
      debugPrint(metrics.renderTable());
      debugPrint(table.toString());
      debugPrint(
        'stages walked: $stagesRun/${stages.length}  •  '
        'screenshots → $shotsDir  •  metrics → ${mDir.path}',
      );

      // The stack (languages/frameworks) is deterministic and MUST be present;
      // the intent stages the user described MUST have produced their tags.
      int n(String c) => finalTags[c]?.length ?? 0;
      expect(
        controller.messages.isNotEmpty,
        isTrue,
        reason: 'the live host should have produced interview messages',
      );
      for (final cat in const [
        'platforms',
        'objectives',
        'features',
        'databases',
        'languages',
        'frameworks',
      ]) {
        expect(
          n(cat),
          greaterThan(0),
          reason: 'setup produced NO "$cat" tags:\n$table',
        );
      }
      final shots = Directory(shotsDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(
        shots.length,
        greaterThanOrEqualTo(stages.length),
        reason: 'every setup stage should be screenshotted',
      );
    },
    skip: !hasCreds,
    timeout: const Timeout(Duration(minutes: 18)),
  );
}
