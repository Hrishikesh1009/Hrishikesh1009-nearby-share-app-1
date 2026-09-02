import 'dart:async';

import 'package:flutter_nearby_connections/flutter_nearby_connections.dart';

import '../models/peer_device.dart';
import 'discovery_service.dart';

/// Layer 1: the OS-managed local link — Wi-Fi Direct + Bluetooth via
/// Google's Nearby Connections API on Android, Multipeer Connectivity on
/// iOS — exposed uniformly by `flutter_nearby_connections`. This is the
/// preferred layer: the OS negotiates the fastest available radio for us.
///
/// Important: we only use this plugin's session for *discovery and
/// handshake*. Once a peer is selected, `NearbyShareEngine` opens our own
/// raw `Socket` (see `core/transport/`) for the actual file bytes, so
/// chunking, backpressure, resume, and encryption all stay under our
/// control instead of the plugin's own (HTTP-adjacent) message channel.
class NearbyDiscoveryService implements DiscoveryService {
  final _eventsController = StreamController<PeerEvent>.broadcast();
  final NearbyService _nearbyService = NearbyService();
  // The plugin's own `stateChangedSubscription` returns a bare (untyped)
  // `StreamSubscription`, not `StreamSubscription<List<Device>>`.
  StreamSubscription? _stateSub;
  bool _active = false;

  @override
  TransportLayer get layer => TransportLayer.nearby;

  @override
  Stream<PeerEvent> get events => _eventsController.stream;

  @override
  bool get isActive => _active;

  /// The plugin's raw device stream, exposed so [NearbyShareEngine] can
  /// request a native connection (`invitePeer`) before opening the TCP
  /// socket, and can send tiny control messages (e.g. "here is my
  /// socket port") over the plugin's own channel prior to that.
  NearbyService get raw => _nearbyService;

  @override
  Future<void> start({required String localDeviceName}) async {
    if (_active) return;

    await _nearbyService.init(
      serviceType: 'nearbyshare',
      deviceName: localDeviceName,
      strategy: Strategy.P2P_CLUSTER,
      callback: (isRunning) async {
        if (isRunning) {
          await _nearbyService.stopBrowsingForPeers();
          await _nearbyService.startBrowsingForPeers();
          await _nearbyService.stopAdvertisingPeer();
          await _nearbyService.startAdvertisingPeer();
        }
      },
    );

    final seen = <String>{};
    _stateSub = _nearbyService.stateChangedSubscription(callback: (devices) {
      final currentIds = <String>{};
      for (final device in devices) {
        final id = 'nearby:${device.deviceId}';
        currentIds.add(id);
        final peer = PeerDevice(
          id: id,
          name: device.deviceName,
          layer: TransportLayer.nearby,
          lastSeen: DateTime.now(),
          nearbyEndpointId: device.deviceId,
        );
        if (seen.add(id)) {
          _eventsController.add(PeerFound(peer));
        }
      }
      final lost = seen.difference(currentIds);
      for (final id in lost) {
        seen.remove(id);
        _eventsController.add(PeerLost(id, TransportLayer.nearby));
      }
    });

    _active = true;
  }

  @override
  Future<void> stop() async {
    if (!_active) return;
    await _stateSub?.cancel();
    await _nearbyService.stopBrowsingForPeers();
    await _nearbyService.stopAdvertisingPeer();
    _active = false;
  }
}
