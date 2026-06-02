// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'call_system_exporter.dart';
import 'twiml_exporter.dart';
import 'telnyx_exporter.dart';
import 'asterisk_exporter.dart';
import 'amazon_connect_exporter.dart';
import 'voip_ms_exporter.dart';

/// Every export target. The portable JSON is the lossless source; the provider
/// exporters map it onto specific backends. "Deploy to Nexus" (managed) uses the
/// portable artifact server-side, so it isn't a separate exporter here.
final List<CallSystemExporter> kCallSystemExporters = [
  const PortableJsonExporter(),
  const VoipMsExporter(),
  const TwimlExporter(),
  const TelnyxExporter(),
  const AsteriskExporter(),
  const AmazonConnectExporter(),
];
