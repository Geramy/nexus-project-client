// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:nexus_projects_client/features/docker/docker_view.dart';
import 'package:nexus_projects_client/features/main/widgets/builds_center.dart';
import 'package:nexus_projects_client/features/main/widgets/deployments_center.dart';

/// "Launch" — the single customer-facing home for everything that gets an app
/// built, packaged and put live. Consolidates what used to be three separate
/// nav entries (Builds & CI, Docker, Deployments) into one tabbed view.
class LaunchCenter extends StatelessWidget {
  const LaunchCenter({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Launch',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Builds'),
              Tab(text: 'Packaging'),
              Tab(text: 'Live Sites'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [BuildsCenter(), DockerView(), DeploymentsCenter()],
            ),
          ),
        ],
      ),
    );
  }
}
