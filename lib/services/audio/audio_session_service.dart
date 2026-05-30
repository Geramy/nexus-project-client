// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:audio_session/audio_session.dart';

/// Configures the platform audio session for voice communication.
///
/// This is the foundation for real AEC (Acoustic Echo Cancellation) and
/// noise suppression, exactly as implemented in lemonade_mobile.
///
/// - On iOS: Engages AVAudioSessionMode.voiceChat (routes through the
///   voice-processing IO unit that provides echo cancellation + noise suppression).
/// - On Android: Uses AndroidAudioUsage.voiceCommunication + the recorder's
///   voiceCommunication audio source (enables hardware AEC when available).
///
/// Must be called before starting microphone capture for Coordinator voice calls.
class AudioSessionService {
  bool _configured = false;

  Future<void> ensureVoiceChatSession() async {
    if (_configured) return;

    try {
      final session = await AudioSession.instance;

      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          usage: AndroidAudioUsage.voiceCommunication,
          contentType: AndroidAudioContentType.speech,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      await session.setActive(true);

      _configured = true;
    } catch (e) {
      // On platforms where this is not supported (or during testing),
      // we continue — the recorder + vad will still function.
      // In production this should be rare.
    }
  }

  Future<void> deactivate() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    _configured = false;
  }
}
