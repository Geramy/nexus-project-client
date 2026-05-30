// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:nexus_projects_client/infrastructure/inference/inference_client.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/services/tts_voices.dart';

/// Text-to-Speech service for the Project Coordinator voice mode.
/// Uses the server's /audio/speech endpoint (via InferenceClient) and plays via just_audio.
// TODO(migrate): InferenceClient? → InferenceBackend
class TtsService {
  final InferenceClient? inferenceClient;
  /// Optional TTS model id. When null the server/default is used.
  final String? ttsModel;
  /// Configured default voice (Kokoro id, e.g. 'af_heart'). Per-call [voice]
  /// overrides this; both fall back to [kDefaultTtsVoice].
  final String? defaultVoice;
  final AudioPlayer _player = AudioPlayer();

  TtsService({this.inferenceClient, this.ttsModel, this.defaultVoice});

  /// Synthesize [text] to an mp3 file and return its path. The file is RETAINED
  /// so the chat session can replay it; the caller owns its lifetime.
  /// Returns null when there's no client, no audio, or synthesis fails.
  Future<String?> synthesize(String text, {String? voice}) async {
    if (text.trim().isEmpty || inferenceClient == null) return null;
    try {
      final result = await inferenceClient!.generateSpeech(
        input: text,
        model: ttsModel,
        voice: voice ?? defaultVoice ?? kDefaultTtsVoice,
        responseFormat: 'mp3',
      );
      if (result.audioBytes.isEmpty) return null;

      // Persist under Application Support (survives restarts) so a saved session
      // can replay the reply audio — temp dir would be cleared between runs.
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/coordinator_audio');
      if (!await dir.exists()) await dir.create(recursive: true);
      final filePath = '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      await File(filePath).writeAsBytes(result.audioBytes, flush: true);
      return filePath;
    } catch (e) {
      // Don't crash the voice loop, but make the failure visible — a silently
      // swallowed TTS 404 looks like "the AI isn't talking back".
      debugPrint('[Voice] TTS synth failed (model=${ttsModel ?? "(default)"}): $e');
      return null;
    }
  }

  /// Play an already-synthesized file and wait for playback to finish.
  Future<void> playFile(String path) async {
    try {
      await _player.setAudioSource(AudioSource.file(path));
      await _player.play();
      await _player.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed || s == ProcessingState.idle)
          .timeout(const Duration(seconds: 60), onTimeout: () => ProcessingState.idle);
    } catch (e) {
      debugPrint('[Voice] TTS playback failed: $e');
    }
  }

  /// Convenience: synthesize + play, then delete the temp file (used when the
  /// audio doesn't need to be retained for replay).
  Future<void> speak(String text, {String? voice}) async {
    final path = await synthesize(text, voice: voice);
    if (path == null) return;
    await playFile(path);
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
