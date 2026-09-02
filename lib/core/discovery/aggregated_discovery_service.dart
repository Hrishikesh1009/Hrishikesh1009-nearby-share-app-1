import 'dart:async';

import '../models/peer_device.dart';
import 'ble_discovery_service.dart';
import 'discovery_service.dart';
import 'mdns_discovery_service.dart';
import 'nearby_discovery_service.dart';

/// Runs all three discovery layers concurrently and merges them into one
/// peer list for the UI, applying the failover preference order —
/// Nearby/Multipeer > mDNS > BLE — when the *same physical device* is
/// visible on more than one layer at once.
///
/// Peers are deduplicated by [PeerDevice.name] as a practical stand-in for
/// "same device": the three layers have no shared identity token by
/// design (BLE advertises a local name, mDNS a service name, Nearby a
/// display name), and in this codebase's flow the transfer initiator always
/// sets [localDeviceName] to the same human-readable name across all three
/// starts, so it round-trips consistently.
class AggregatedDiscoveryService {
  AggregatedDiscoveryService({required int transferPort})
      : _layers = [
          NearbyDiscoveryService(),
          MdnsDiscoveryService(transferPort: transferPort),
          BleDiscoveryService(),
        ];

  final List<DiscoveryService> _layers;
  final Map<String, PeerDevice> _byName = {};
  final _mergedController = StreamController<List<PeerDevice>>.broadcast();
  final List<StreamSubscription<PeerEvent>> _subs = [];

  static const _layerPriority = {
    TransportLayer.nearby: 0,
    TransportLayer.mdns: 1,
    TransportLayer.ble: 2,
  };

  /// The live, de-duplicated, priority-sorted peer list — this is exactly
  /// what the "Nearby Devices" / radar screen renders.
  Stream<List<PeerDevice>> get peers => _mergedController.stream;

  NearbyDiscoveryService get nearbyLayer => _layers[0] as NearbyDiscoveryService;
  MdnsDiscoveryService get mdnsLayer => _layers[1] as MdnsDiscoveryService;
  BleDiscoveryService get bleLayer => _layers[2] as BleDiscoveryService;

  Future<void> start({required String localDeviceName}) async {
    for (final layer in _layers) {
      _subs.add(layer.events.listen((event) => _onEvent(event)));
      // Layers fail independently: BLE permission denial, for instance,
      // must not prevent mDNS/Nearby from working.
      unawaited(layer.start(localDeviceName: localDeviceName).catchError((Object e) {
        // ignore: avoid_print
        print('Discovery layer ${layer.layer} failed to start: $e');
      }));
    }
  }

  void _onEvent(PeerEvent event) {
    switch (event) {
      case PeerFound(:final device):
        final existing = _byName[device.name];
        if (existing == null ||
            _layerPriority[device.layer]! <= _layerPriority[existing.layer]!) {
          _byName[device.name] = device;
        }
        _emit();
        break;
      case PeerLost(:final deviceId, :final layer):
        final match = _byName.entries
            .where((e) => e.value.id == deviceId && e.value.layer == layer)
            .map((e) => e.key)
            .toList();
        for (final name in match) {
          _byName.remove(name);
        }
        _emit();
        break;
    }
  }

  void _emit() {
    final list = _byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    _mergedController.add(list);
  }

  Future<void> stop() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    for (final layer in _layers) {
      await layer.stop();
    }
    _byName.clear();
  }
}
