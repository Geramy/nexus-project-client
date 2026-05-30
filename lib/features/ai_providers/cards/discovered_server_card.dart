// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import 'package:nexus_projects_client/infrastructure/lemonade/models/discovered_server.dart';
class DiscoveredServerCard extends StatelessWidget {
  final DiscoveredServer server;
  final bool isSelected;

  const DiscoveredServerCard({super.key, required this.server, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isSelected ? Icons.check_circle : Icons.wifi_tethering,
          color: isSelected ? Colors.teal : Colors.grey,
        ),
        title: Text(server.hostname),
        subtitle: Text(server.url),
        trailing: isSelected
            ? const Text('Configured', style: TextStyle(fontSize: 11, color: Colors.teal))
            : const SizedBox.shrink(),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server "${server.hostname}" at ${server.url}')),
          );
        },
      ),
    );
  }
}
