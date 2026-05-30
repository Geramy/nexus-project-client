// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Admin console widget — 5-tab shell assembling Dashboard, Models, Backends, System, Logs.
/// Ported from ~/IdeaProjects/lemonade_mobile/lib/screens/admin_console_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/infrastructure/lemonade/models/server_config.dart';
import 'package:nexus_projects_client/features/ai_providers/providers/admin_console_provider.dart';

import 'dashboard_tab.dart';
import 'models_tab.dart';
import 'backends_tab.dart';
import 'system_info_tab.dart';
import 'logs_tab.dart';

/// Five-tab console for managing the connected Lemonade server.
class AdminConsoleWidget extends ConsumerWidget {
  final ServerConfig server;

  const AdminConsoleWidget({super.key, required this.server});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(adminConsoleClientProvider);

    if (client == null) {
      return Scaffold(
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Select a server first to access admin features.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Admin · ${server.name}'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Dashboard', icon: Icon(Icons.dashboard)),
              Tab(text: 'Models', icon: Icon(Icons.model_training)),
              Tab(text: 'Backends', icon: Icon(Icons.developer_board)),
              Tab(text: 'System', icon: Icon(Icons.computer)),
              Tab(text: 'Logs', icon: Icon(Icons.receipt_long)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminDashboardTab(),
            AdminModelsTab(),
            AdminBackendsTab(),
            AdminSystemInfoTab(),
            AdminLogsTab(),
          ],
        ),
      ),
    );
  }
}
