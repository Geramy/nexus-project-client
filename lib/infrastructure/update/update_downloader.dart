// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloads a release installer to a staging directory, fetches the published
/// `SHA256SUMS.txt`, and verifies the download against it. Streaming throughout
/// so a ~25 MB installer never sits fully in memory.
class UpdateDownloader {
  UpdateDownloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// `<temp>/nexus-updates`, created on demand. Cleared of stale files first so
  /// a previous failed/abandoned download never lingers.
  Future<Directory> _stagingDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'nexus-updates'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Removes any previously-staged installer files.
  Future<void> cleanStaging() async {
    try {
      final dir = await _stagingDir();
      await for (final entity in dir.list()) {
        if (entity is File) await entity.delete();
      }
    } catch (_) {
      // Best-effort cleanup; never block an update on it.
    }
  }

  /// Streams [url] into `<staging>/<filename>`, reporting progress as
  /// (receivedBytes, totalBytes?) — total is null if the server omits it.
  /// Returns the written file. Throws on a non-200 or a write error.
  Future<File> download(
    String url,
    String filename, {
    required void Function(int received, int? total) onProgress,
  }) async {
    final dir = await _stagingDir();
    final dest = File(p.join(dir.path, filename));
    if (await dest.exists()) await dest.delete();

    final req = http.Request('GET', Uri.parse(url));
    final resp = await _client.send(req);
    if (resp.statusCode != 200) {
      throw HttpException(
        'Download failed (${resp.statusCode})',
        uri: Uri.parse(url),
      );
    }

    final total = resp.contentLength;
    var received = 0;
    final sink = dest.openWrite();
    try {
      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return dest;
  }

  /// Downloads and parses `SHA256SUMS.txt` (lines of `"<hex>  <name>"`) into a
  /// map of asset name → lowercase hex digest.
  Future<Map<String, String>> fetchChecksums(String url) async {
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException(
        'Checksums fetch failed (${resp.statusCode})',
        uri: Uri.parse(url),
      );
    }
    return parseChecksums(resp.body);
  }

  /// Parses the body of a `SHA256SUMS.txt` file. Tolerates the `sha256sum`
  /// binary-mode `*` marker and extra whitespace. Exposed for unit tests.
  static Map<String, String> parseChecksums(String body) {
    final out = <String, String>{};
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      // `<64-hex>  <name>` or `<64-hex> *<name>`
      final sp = line.indexOf(RegExp(r'\s'));
      if (sp < 0) continue;
      final hex = line.substring(0, sp).toLowerCase();
      var name = line.substring(sp).trim();
      if (name.startsWith('*')) name = name.substring(1);
      if (hex.length == 64 && name.isNotEmpty) out[name] = hex;
    }
    return out;
  }

  /// Streams [file] through SHA-256 and compares (case-insensitively) to
  /// [expectedHex]. Returns true on a match.
  static Future<bool> verify(File file, String expectedHex) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedHex.toLowerCase();
  }

  void dispose() => _client.close();
}
