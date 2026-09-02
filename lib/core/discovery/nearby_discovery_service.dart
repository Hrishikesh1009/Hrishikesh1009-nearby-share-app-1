import 'dart:async';

import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

import '../models/peer_device.dart';
import 'discovery_service.dart';

/// Layer 1: real Wi-Fi Direct via `flutter_p2p_connection` (Android only —
/// see below). Every device that runs this simultaneously:
///  - **hosts** its own Wi-Fi Direct group (`FlutterP2pHost.createGroup`)
///    and advertises its join credentials over BLE, so other devices can
///    find and connect to *us*;
///  - **scans** via BLE for other devices' host advertisements
///    (`FlutterP2pClient.startScan`), which is what populates [events].
///
/// BLE here is discovery/credential-exchange only, same spirit as Layer 3
/// — the actual Wi-Fi Direct group formation is what creates the shared
/// network segment. Once a client joins a host's group, both sides are on
/// that segment and dial *our own* raw `Socket` on `NearbyShareEngine`'s
/// existing transfer port (`core/transport/`), never this plugin's
/// separate `broadcastFile`/`downloadFile` API — same reasoning as every
/// other layer: encryption, chunking, and resume stay entirely under our
/// control. See [connectAndGetHostIp], which `NearbyShareEngine.sendFiles`
/// calls to actually join a discovered peer's group and get a dialable IP
/// before opening that socket.
///
/// **Android only.** `flutter_p2p_connection` registers no iOS
/// implementation; on iOS this layer never activates (Layers 2 and 3
/// still work). Apple's nearest equivalent is Multipeer Connectivity,
/// which is a materially different API surface — out of scope here.
class NearbyDiscoveryService implements DiscoveryService {
  final FlutterP2pHost _host = FlutterP2pHost();
  final FlutterP2pClient _client = FlutterP2pClient();
  final _eventsController = StreamController<PeerEvent>.broadcast();
  final Map<String, BleDiscoveredDevice> _known = {};

  bool _active = false;

  @override
  TransportLayer get layer => TransportLayer.nearby;

  @override
  Stream<PeerEvent> get events => _eventsController.stream;

  @override
  bool get isActive => _active;

  @override
  Future<void> start({required String localDeviceName}) async {
    if (_active) return;

    await _host.askP2pPermissions();
    await _host.askBluetoothPermissions();

    await _host.initialize();
    await _client.initialize();

    // Advertise: our own group, so other devices' clients can find us.
    await _host.createGroup(advertise: true);

    _active = true;
    unawaited(_scanLoop());
  }

  /// `FlutterP2pClient.startScan` auto-stops after its `timeout` — loop it
  /// so discovery stays continuous for as long as this layer is active,
  /// matching every other [DiscoveryService]'s long-running behavior.
  Future<void> _scanLoop() async {
    while (_active) {
      try {
        final sub = await _client.startScan(
          _onDevicesFound,
          timeout: const Duration(seconds: 20),
        );
        await sub.asFuture<void>();
      } catch (_) {
        // Transient scan failure (BLE momentarily off, permission race on
        // first launch, etc.) — brief backoff, then the loop retries.
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  void _onDevicesFound(List<BleDiscoveredDevice> devices) {
    final currentIds = <String>{};
    for (final device in devices) {
      final id = 'nearby:${device.deviceAddress}';
      currentIds.add(id);
      _known[id] = device;
      _eventsController.add(PeerFound(PeerDevice(
        id: id,
        name: device.deviceName,
        layer: TransportLayer.nearby,
        lastSeen: DateTime.now(),
        nearbyEndpointId: device.deviceAddress,
      )));
    }
    final lost = _known.keys.toSet().difference(currentIds);
    for (final id in lost) {
      _known.remove(id);
      _eventsController.add(PeerLost(id, TransportLayer.nearby));
    }
  }

  /// Joins the Wi-Fi Direct group of a peer previously seen in [events]
  /// (identified by [deviceAddress] — [PeerDevice.nearbyEndpointId]) and
  /// returns the host's gateway IP once connected, or `null` if the
  /// device isn't currently known. `NearbyShareEngine.sendFiles` dials its
  /// own encrypted socket on this IP:port — see the class doc comment.
  ///
  /// Note this associates the device's Wi-Fi radio with the peer's
  /// hotspot for the duration of the transfer, same real tradeoff any
  /// Wi-Fi Direct transfer makes — normal Wi-Fi/internet connectivity is
  /// unavailable until [disconnectFromPeer] (or another transfer) restores
  /// it.
  Future<String?> connectAndGetHostIp(String deviceAddress) async {
    final device = _known['nearby:$deviceAddress'];
    if (device == null) return null;

    await _client.connectWithDevice(device);
    final state = await _client.streamHotspotState().firstWhere(
          (s) => s.isActive && s.hostGatewayIpAddress != null,
        );
    return state.hostGatewayIpAddress;
  }

  /// Leaves whatever peer group [connectAndGetHostIp] joined, restoring
  /// this device's normal Wi-Fi connectivity. Safe to call even if not
  /// currently connected to a peer.
  Future<void> disconnectFromPeer() => _client.disconnect();

  @override
  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    await _client.stopScan();
    await _client.disconnect();
    await _host.removeGroup();
    await _client.dispose();
    await _host.dispose();
    _known.clear();
  }
}
