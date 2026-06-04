// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/app/router.dart';
import 'package:nexus_projects_client/core/providers/theme_provider.dart';
import 'package:nexus_projects_client/features/update/update_banner.dart';
import 'package:nexus_projects_client/shared/ui/app_theme.dart';

class NexusProjectsApp extends ConsumerWidget {
  const NexusProjectsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(appThemeNotifierProvider);
    return MaterialApp.router(
      title: 'Nexus Projects',
      // The selected theme fully determines the look (incl. brightness), so we
      // drive a single `theme` rather than light/dark + ThemeMode.system.
      theme: AppTheme.of(choice),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      // Float the global "update available / downloading" banner above every
      // route without coupling it to any one screen.
      builder: (context, child) =>
          UpdateBannerHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
