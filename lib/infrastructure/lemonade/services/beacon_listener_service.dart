// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Ported exactly from ~/IdeaProjects/lemonade_mobile/lib/services/beacon_listener_service.dart
/// Listens for UDP beacons broadcast by local Lemonade servers (port 13305 by default).
/// Only relevant for self-managed local Lemonade instances. Routed/routed servers
/// (nexus-projects-server) do not broadcast these beacons.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/discovered_server.dart';

class BeaconListenerService {
  /// Default UDP port to listen on. Must match the port used by
  /// the Lemonade server's NetworkBeacon::startBroadcasting() call.
  /// Lemonade currently broadcasts on its API port (13305).
  static const int defaultPort = 13305;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSub;
  bool _isListening = false;
  final int _port;

  final _discoveredController = StreamController<DiscoveredServer>.broadcast();
  Stream<DiscoveredServer> get onServerDiscovered =>
      _discoveredController.stream;

  bool get isListening => _isListening;

  BeaconListenerService({int port = defaultPort}) : _port = port;

  Future<void> startListening() async {
    if (_isListening) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
        reusePort: true,
      );
      _socket!.broadcastEnabled = true;
      _isListening = true;
      _socketSub = _socket!.listen(
        _onSocketEvent,
        onError: (_) {},
        onDone: () {},
      );
    } catch (_) {
      // Bind failure typically means a same-machine Lemonade server already
      // owns the port. The app stays usable; user adds the server manually.
      _isListening = false;
      _socket = null;
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;

    while (true) {
      final datagram = socket.receive();
      if (datagram == null) return;
      _handleDatagram(datagram);
    }
  }

  /// Extract the port from a URL string (e.g. "http://10.0.0.1:8000" -> "8000").
  String? _extractPort(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.hasPort) return uri.port.toString();
    } catch (_) {}
    return null;
  }

  /// Build the server URL from the UDP packet's source IP and the port
  /// advertised in the beacon's url field.
  String _buildUrl(String sourceIp, String beaconUrl) {
    final port = _extractPort(beaconUrl);
    if (port != null) {
      return 'http://$sourceIp:$port';
    }
    return 'http://$sourceIp';
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final data = utf8.decode(datagram.data);
      final json = jsonDecode(data) as Map<String, dynamic>;

      if (json['service'] != 'lemonade') return;

      final sourceIp = datagram.address.address;
      final beaconUrl = json['url'] as String? ?? '';
      final resolvedUrl = _buildUrl(sourceIp, beaconUrl);

      _discoveredController.add(
        DiscoveredServer(
          hostname: json['hostname'] ?? 'Unknown',
          url: resolvedUrl,
          lastSeen: DateTime.now(),
          address: sourceIp,
        ),
      );
    } catch (_) {
      // Bad packet — ignore.
    }
  }

  void stopListening() {
    _isListening = false;
    _socketSub?.cancel();
    _socketSub = null;
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    stopListening();
    _discoveredController.close();
  }
}
