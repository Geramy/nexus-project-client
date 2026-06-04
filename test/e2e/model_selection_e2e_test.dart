// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// LIVE guard for MODEL/COLLECTION SELECTION. Catches the class of bug where the
// coordinator silently uses the wrong model (e.g. a small raw fallback like
// Qwen3.5-4B) instead of the product's default Omni collection. Verifies:
//   1. the default coordinator model IS the Omni collection LMX-Omni-52B-Halo
//      (kDefaultOmniCollection) — not a decomposed/fallback raw model;
//   2. the routed gateway actually SERVES a chat completion for that id (no
//      503/500, real content) — i.e. the model is the one truly used.
//
// Gated on NEXUS_EMAIL / NEXUS_PASSWORD; runs on every push via e2e.yml. Fast
// (one tiny chat call), no UI/device needed.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/infrastructure/inference/inference_backend_factory.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/services/persona_model_resolver.dart'
    show kDefaultOmniCollection;
import 'package:nexus_projects_client/infrastructure/models/ui/inference_server.dart'
    as ui_model;
import 'package:nexus_projects_client/infrastructure/nexus/nexus_account_client.dart';

import 'support/metrics.dart';
import 'support/model_picker.dart';

void main() {
  final email = Platform.environment['NEXUS_EMAIL'];
  final password = Platform.environment['NEXUS_PASSWORD'];
  final gatewayEnv = Platform.environment['NEXUS_GATEWAY'];
  final gateway = (gatewayEnv == null || gatewayEnv.trim().isEmpty)
      ? 'https://api.nexus-projects.ai'
      : gatewayEnv.trim();
  final override = Platform.environment['NEXUS_MODEL'];
  final skip =
      (email == null || email.isEmpty || password == null || password.isEmpty)
      ? 'model-selection guard skipped: set NEXUS_EMAIL and NEXUS_PASSWORD'
      : false;

  test(
    'LIVE: coordinator default is the LMX-Omni-52B-Halo collection AND it serves chat',
    () async {
      final acct = NexusAccountClient(baseUrl: gateway);
      final auth = await acct.login(
        email: email!,
        password: password!,
        deviceId: 'ci-model-check',
        deviceName: 'github-ci',
        appName: kNexusAppName,
      );
      expect(auth.token, isNotEmpty);

      // ── 1. Collection selection. Default MUST be the Omni collection. ─────
      final resolved = await resolveCoordinatorModel(
        gateway: gateway,
        token: auth.token,
        override: override,
      );
      if (override == null || override.trim().isEmpty) {
        expect(
          resolved.collection,
          kDefaultOmniCollection,
          reason:
              'the default coordinator model must be the Omni collection '
              '"$kDefaultOmniCollection" — NOT a decomposed/raw fallback model. '
              'Got "${resolved.collection}".',
        );
      }
      // We address the collection directly (the router serves the collection id).
      expect(resolved.chat, resolved.collection);

      // ── 2. The router must actually SERVE that model. ────────────────────
      final server = ui_model.InferenceServer(
        id: 'routed',
        name: 'Nexus Router',
        baseUrl: gateway,
        apiKey: auth.token,
        providerType: 'routed',
      );
      final backend = backendForServer(server, agentName: 'ModelCheck');
      final sw = Stopwatch()..start();
      final resp = await backend.createChatCompletion(
        model: resolved.chat,
        messages: const [
          {'role': 'user', 'content': 'Reply with exactly the word: ok'},
        ],
        maxTokens: 16,
        temperature: 0,
      );
      sw.stop();
      expect(
        resp.choices,
        isNotEmpty,
        reason:
            'the router did not serve a chat completion for '
            '"${resolved.chat}" — the model is wrong or not available.',
      );
      final content = (resp.choices.first.message.content ?? '').trim();
      expect(
        content,
        isNotEmpty,
        reason: 'served model "${resolved.chat}" returned no content.',
      );

      // ── Record what was selected + served, for the stats. ────────────────
      final metrics = MetricsLog('model_selection');
      metrics.record(
        'model',
        'collection=${resolved.collection} served chat OK',
        sw.elapsed,
        ok: true,
        extra: {
          'collection': resolved.collection,
          'chat': resolved.chat,
          'reply_chars': content.length,
        },
      );
      await metrics.flush();
      debugPrint(
        'model selection → collection=${resolved.collection} '
        'chat=${resolved.chat} reply="$content" (${sw.elapsed.inMilliseconds}ms)',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
