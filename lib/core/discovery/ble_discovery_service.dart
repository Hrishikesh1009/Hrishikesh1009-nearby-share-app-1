import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/peer_device.dart';
import 'discovery_service.dart';

/// Layer 3: Bluetooth LE, used purely for discovery/handshake — never for
/// the file stream. BLE's throughput (tens of KB/s at best) is unusable for
/// multi-gigabyte transfers, so once a peer is found here the engine's
/// failover logic still needs Layer 1 or 2 to actually move bytes; a
/// BLE-only peer shows in the list but a transfer attempt against it will
/// surface a clear "no data layer available" error rather than silently
/// crawling over BLE.
///
/// We identify peers by advertised local name; a real product would use a
/// custom service UUID + manufacturer data to carry a stable device id
/// without relying on the OS's (sometimes throttled) name field.
class BleDiscoveryService implements DiscoveryService {
  final _eventsController = StreamController<PeerEvent>.broadcast();
  final Map<String, PeerDevice> _known = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _staleSweeper;
  bool _active = false;

  static const _staleAfter = Duration(seconds: 12);

  @override
  TransportLayer get layer => TransportLayer.ble;

  @override
  Stream<PeerEvent> get events => _eventsController.stream;

  @override
  bool get isActive => _active;

  @override
  Future<void> start({required String localDeviceName}) async {
    if (_active) return;

    // Advertising a name from a Flutter app requires a native peripheral
    // role that flutter_blue_plus does not expose directly; discovery here
    // is intentionally scan-only. Layer 1 (Nearby/Multipeer) carries the
    // symmetric "peers see us too" advertisement.
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      removeIfGone: _staleAfter,
    );

    _staleSweeper = Timer.periodic(const Duration(seconds: 4), (_) => _sweepStale());
    _active = true;
  }

  void _onScanResults(List<ScanResult> results) {
    final now = DateTime.now();
    for (final result in results) {
      final name = result.advertisementData.advName.isNotEmpty
          ? result.advertisementData.advName
          : result.device.platformName;
      if (name.isEmpty) continue;

      final id = 'ble:${result.device.remoteId.str}';
      final device = PeerDevice(
        id: id,
        name: name,
        layer: TransportLayer.ble,
        lastSeen: now,
      );
      final isNew = !_known.containsKey(id);
      _known[id] = device;
      if (isNew) {
        _eventsController.add(PeerFound(device));
      }
    }
  }

  void _sweepStale() {
    final now = DateTime.now();
    final stale = _known.values.where((d) => now.difference(d.lastSeen) > _staleAfter).toList();
    for (final device in stale) {
      _known.remove(device.id);
      _eventsController.add(PeerLost(device.id, TransportLayer.ble));
    }
  }

  @override
  Future<void> stop() async {
    if (!_active) return;
    _staleSweeper?.cancel();
    await _scanSub?.cancel();
    await FlutterBluePlus.stopScan();
    _known.clear();
    _active = false;
  }
}
