// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:typed_data';

/// Result of `POST /v1/audio/speech` — raw audio bytes plus the MIME.
class TtsResult {
  final Uint8List audioBytes;
  final String mime;
  const TtsResult({required this.audioBytes, required this.mime});
}

/// Result of `POST /v1/audio/transcriptions`.
class TranscriptionResult {
  final String text;
  TranscriptionResult({required this.text});
  factory TranscriptionResult.fromJson(Map<String, dynamic> json) =>
      TranscriptionResult(text: json['text'] as String? ?? '');
}
