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

  // The user's side of the conversation — one informative answer per turn. The
  // host (live AI) decides exactly what it asks; we answer in order and stop
  // when the host moves to plan generation (refining) or we hit the turn cap.
  const answers = <String>[
    'I want to build a small cross-platform to-do / task tracker app for '
        'personal productivity.',
    'It is for general consumer / personal use — not a specific regulated '
        'industry.',
    'Target platforms: iOS, Android, and Web.',
    'Core features: create and edit tasks, mark them complete, due dates, and '
        'local reminders/notifications.',
    'Use a local on-device database (SQLite). No backend server is needed yet.',
    'Keep the dependency list minimal — just the essentials for state and '
        'storage.',
    'No external third-party services or integrations are needed for now.',
    'That covers everything — please finalize and generate the plans.',
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

      // ── Steps 2..N: walk the host's questions, timing each turn. ─────────
      final composer = find
          .descendant(
            of: find.byType(SetupInterviewPanel),
            matching: find.byType(TextField),
          )
          .first;

      // Cap turns AND total interview time: live turns can be slow (a cold
      // first turn streams a preamble + tool calls before it asks anything), so
      // give each turn room but stop the whole loop on a wall-clock budget.
      final interviewDeadline = DateTime.now().add(const Duration(minutes: 9));
      var turnsRun = 0;
      String? lastQ; // detect a stalled host (same prompt, no progress)
      var stall = 0;
      for (
        var i = 0;
        i < answers.length &&
            !controller.refining &&
            DateTime.now().isBefore(interviewDeadline);
        i++
      ) {
        // Make sure the composer is actually ready (host idle, or a question is
        // waiting) before sending — otherwise the send button is a spinner.
        await waitTurn(150);
        final send = find.byIcon(Icons.send);
        if (send.evaluate().isEmpty) {
          // Still mid-turn with nothing to answer; capture state and stop.
          await shot('turn_${(i + 1).toString().padLeft(2, '0')}_busy');
          break;
        }

        // If the host keeps showing the SAME prompt, it has stopped advancing
        // the interview (a weak model) — don't record no-op repeat turns.
        final qNow = latestHostText();
        if (qNow == lastQ) {
          if (++stall >= 2) break;
        } else {
          stall = 0;
        }
        lastQ = qNow;

        await tester.enterText(composer, answers[i]);
        await tester.pump(const Duration(milliseconds: 120));
        final sw = Stopwatch()..start();
        await tester.tap(send);
        await tester.pump(const Duration(milliseconds: 120));
        await waitTurn(150);
        sw.stop();
        turnsRun++;

        final q = latestHostText();
        metrics.record(
          'qa_step',
          'turn ${i + 1}: ${snip(q)}',
          sw.elapsed,
          extra: {
            'turn': i + 1,
            'question_len': q.length,
            'answer': answers[i],
            'model': model,
          },
        );
        transcript
          ..writeln('\n── turn ${i + 1}  (${sw.elapsed.inMilliseconds} ms) ──')
          ..writeln('Q: $q')
          ..writeln('A: ${answers[i]}');

        await settle(300);
        await shot('turn_${(i + 1).toString().padLeft(2, '0')}');
      }

      // ── Finalize → generate plans (forces the refine phase). ─────────────
      if (!controller.refining) {
        final fin = find.text('Finalize & generate plans');
        if (fin.evaluate().isNotEmpty) {
          final sw = Stopwatch()..start();
          await tester.tap(fin);
          await tester.pump(const Duration(milliseconds: 150));
          // Finalize generates the plan files; wait (bounded) for busy to clear.
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
      await shot('refine_ready');

      // ── Persist timing + transcript; assert we navigated the real flow. ──
      final mDir = await metrics.flush();
      await File('$shotsDir/transcript.txt').writeAsString(transcript.toString());
      debugPrint(metrics.renderTable());
      debugPrint(transcript.toString());
      debugPrint('screenshots → $shotsDir  •  metrics → ${mDir.path}');

      debugPrint(
        'interview turns run: $turnsRun • refining=${controller.refining}',
      );

      // The deliverables are the screenshots + the timed transcript: assert we
      // genuinely drove the live UI (host produced messages, we ran turns, and
      // every step was screenshotted). `refining` is logged, not required — a
      // slow model may not finish finalize within budget, but the captured
      // walkthrough is still the artifact we ship.
      expect(
        controller.messages.isNotEmpty,
        isTrue,
        reason: 'the live host should have produced interview messages',
      );
      expect(turnsRun, greaterThanOrEqualTo(1), reason: 'at least one Q&A turn');
      expect(
        metrics.metrics.where((m) => m.kind == 'qa_step').length,
        greaterThanOrEqualTo(1),
        reason: 'at least one timed Q&A step recorded',
      );
      final shots = Directory(shotsDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(
        shots.length,
        greaterThanOrEqualTo(3),
        reason: 'each setup step should be screenshotted',
      );
    },
    skip: !hasCreds,
    timeout: const Timeout(Duration(minutes: 18)),
  );
}
