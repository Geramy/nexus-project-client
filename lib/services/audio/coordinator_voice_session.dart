// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:io';

import 'package:nexus_projects_client/features/projects/coordinator_session.dart';
// TODO: migrate to InferenceBackend (via InferenceBackendFactory or LemonadeBackend).
// CoordinatorVoiceSession still uses the deprecated InferenceClient (via the
// coordinatorSession.client) for transcribeAudio.
import 'package:nexus_projects_client/infrastructure/inference/inference_client.dart';
import 'package:nexus_projects_client/services/audio/audio_recorder_service.dart';
import 'package:nexus_projects_client/services/audio/audio_session_service.dart';
import 'package:nexus_projects_client/services/audio/tts_service.dart';

/// Basic voice session for talking to the Project Coordinator.
/// Supports push-to-talk style interaction:
/// 1. User holds/taps to record
/// 2. Transcribe (placeholder for now - will use Lemonade ASR)
/// 3. Send to coordinator via streaming
/// 4. Speak the response
///
/// Full duplex (always-listening with interruption) can be added later
/// by porting more from lemonade_mobile's DuplexVoiceSession + RealtimeAudioSocket.
class CoordinatorVoiceSession {
  final ProjectCoordinatorSession coordinatorSession;
  final AudioRecorderService recorder;
  final TtsService tts;

  final _stateController = StreamController<VoiceState>.broadcast();
  final _transcriptController = StreamController<String>.broadcast();

  bool _isListening = false;

  CoordinatorVoiceSession({
    required this.coordinatorSession,
    required this.recorder,
    required this.tts,
  });

  Stream<VoiceState> get state => _stateController.stream;
  Stream<String> get liveTranscript => _transcriptController.stream;

  bool get isListening => _isListening;

  Future<void> startListening() async {
    if (_isListening) return;

    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      _stateController.add(VoiceState.error);
      return;
    }

    // Real AEC via OS voice processing session (lemonade_mobile pattern)
    await AudioSessionService().ensureVoiceChatSession();

    _isListening = true;
    _stateController.add(VoiceState.listening);

    try {
      await recorder.startRecording();
    } catch (e) {
      _isListening = false;
      _stateController.add(VoiceState.error);
    }
  }

  Future<void> stopListeningAndProcess() async {
    if (!_isListening) return;

    _stateController.add(VoiceState.processing);

    String? audioPath;
    try {
      audioPath = await recorder.stopRecording();
      _isListening = false;

      if (audioPath == null) {
        _stateController.add(VoiceState.idle);
        return;
      }

      // Real transcription via the project's InferenceClient (Lemonade Whisper or compatible)
      // TODO(migrate): replace with InferenceBackend.transcribeAudio once chat/voice paths are updated.
      String transcript = '';
      try {
        final audioFile = File(audioPath);
        if (await audioFile.exists()) {
          final bytes = await audioFile.readAsBytes();
          final result = await coordinatorSession.client.transcribeAudio(
            audioBytes: bytes,
            filename: audioPath.split(Platform.pathSeparator).last,
            // model left default; server chooses best Whisper-compatible
          );
          transcript = result.text.trim();
        }
      } catch (e) {
        transcript = 'Voice input received (transcription unavailable: $e)';
      }

      if (transcript.isEmpty) {
        transcript = 'Voice message (no speech detected)';
      }

      _transcriptController.add(transcript);

      // Send to coordinator (this will use the real streaming path + tool execution)
      final stream = coordinatorSession.streamMessage(transcript);

      StringBuffer responseBuffer = StringBuffer();

      await for (final event in stream) {
        if (event is ChatContentDelta) {
          responseBuffer.write(event.text);
        } else if (event is ChatStreamFinish) {
          final finalText = responseBuffer.toString().isNotEmpty
              ? responseBuffer.toString()
              : (event.contentSoFar);

          if (finalText.isNotEmpty) {
            await tts.speak(finalText);
          }
        }
      }

      _stateController.add(VoiceState.idle);
    } catch (e) {
      _stateController.add(VoiceState.error);
      _isListening = false;
    } finally {
      // Cleanup temp audio file
      if (audioPath != null) {
        try {
          final file = File(audioPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> cancel() async {
    _isListening = false;
    await recorder.stopRecording();
    await tts.stop();
    _stateController.add(VoiceState.idle);
  }

  Future<void> dispose() async {
    await cancel();
    await _stateController.close();
    await _transcriptController.close();
    await recorder.dispose();
    await tts.dispose();
  }
}

enum VoiceState { idle, listening, processing, speaking, error }
