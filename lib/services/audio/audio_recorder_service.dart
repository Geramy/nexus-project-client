// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// Audio recording service for voice conversations with the Project Coordinator.
/// Adapted from lemonade_mobile patterns for consistency.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  /// Check and request microphone permission.
  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording to a temporary file.
  /// Returns the file path.
  Future<String> startRecording() async {
    if (_isRecording) {
      throw StateError('Already recording');
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/coordinator_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 96000,
      ),
      path: path,
    );

    _isRecording = true;
    return path;
  }

  /// Stop recording and return the file path (or null).
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    final path = await _recorder.stop();
    _isRecording = false;
    return path;
  }

  /// Get current amplitude for visual feedback (0.0 - 1.0).
  Future<double> getAmplitude() async {
    try {
      final amp = await _recorder.getAmplitude();
      final dB = amp.current.clamp(-60.0, 0.0);
      return (dB + 60.0) / 60.0;
    } catch (_) {
      return 0.0;
    }
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }

  // ---------------------------------------------------------------------------
  // Streaming PCM mode (for VAD + future realtime ASR, matching lemonade_mobile)
  // ---------------------------------------------------------------------------

  StreamSubscription<Uint8List>? _pcmSub;

  /// Start streaming raw PCM16 mono 16 kHz chunks directly from the mic.
  /// This is required for client-side Silero VAD and low-latency ASR sockets.
  /// Returns the stream you should listen to (and feed to VoiceActivityService.feedAudioChunk).
  Future<Stream<Uint8List>> startPcmStream() async {
    if (_isRecording) {
      throw StateError('Already recording');
    }

    // We want to use the exact RecordConfig from lemonade_mobile for best
    // voice quality (especially the Android voiceCommunication source for AEC).
    //
    // However, we currently have this dependency override in pubspec.yaml:
    //   record_platform_interface: 1.0.2
    // This old interface does **not** support `androidConfig`.
    // It was added as a workaround to make macOS debug builds work with record_linux.
    //
    // → We therefore cannot use androidConfig while the override is active.
    //   Uncomment the androidConfig block below once you remove the override
    //   (or when targeting Android only).
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // androidConfig: const AndroidRecordConfig(
        //   audioSource: AndroidAudioSource.voiceCommunication,
        // ),
      ),
    );

    _isRecording = true;
    return stream;
  }

  /// Stop the PCM stream (if active).
  Future<void> stopPcmStream() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _isRecording = false;
  }
}
