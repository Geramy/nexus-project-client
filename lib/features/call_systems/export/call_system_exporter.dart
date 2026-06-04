// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import '../model/call_system_project.dart';

/// Turns the portable [CallSystemProject] into a specific backend's artifact(s).
/// "Phone systems are phone systems" — the builder targets one model and each
/// exporter maps it onto a provider. [export] returns filename → content (a
/// provider may emit several files). [notes] surfaces anything the mapping can't
/// represent so the user isn't misled.
abstract class CallSystemExporter {
  String get providerKey;
  String get displayName;
  String get artifactExtension;

  Map<String, String> export(CallSystemProject project);

  /// Best-effort caveats for this provider (impedance mismatches, manual steps).
  List<String> notes(CallSystemProject project) => const [];
}

/// The always-correct export: the portable schema itself. Self-serve users take
/// this (plus the referenced audio files) and deploy on any backend; it's also
/// what the Nexus-managed runtime consumes.
class PortableJsonExporter implements CallSystemExporter {
  const PortableJsonExporter();

  @override
  String get providerKey => 'portable';
  @override
  String get displayName => 'Portable (Nexus JSON)';
  @override
  String get artifactExtension => 'json';

  @override
  Map<String, String> export(CallSystemProject project) => {
    'call_system.json': const JsonEncoder.withIndent(
      '  ',
    ).convert(project.toJson()),
  };

  @override
  List<String> notes(CallSystemProject project) => const [
    'This is the complete, lossless project. Pair it with the prompt audio '
        'files to deploy anywhere, or deploy to Nexus for the managed runtime.',
  ];
}
