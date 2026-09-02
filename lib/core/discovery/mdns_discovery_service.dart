import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

import '../models/peer_device.dart';
import 'discovery_service.dart';

/// Layer 2: zero-configuration mDNS/Bonjour discovery on whatever Wi-Fi
/// router network the device is already joined to. This is the fallback
/// when a direct Wi-Fi Direct / Multipeer session isn't available (e.g. the
/// peer is a desktop, or the OS is between association states) but both
/// devices share a LAN.
///
/// We advertise a service carrying the TCP port our
/// `core/transport/` listener is bound to, so a browsing peer can dial us
/// directly with a raw `Socket.connect` — no HTTP, no service discovery
/// round-trip beyond resolving host+port.
class MdnsDiscoveryService implements DiscoveryService {
  MdnsDiscoveryService({required this.transferPort});

  static const String serviceType = '_nearbyshare._tcp';

  /// The port `core/transport/` is listening on, advertised via mDNS TXT.
  final int transferPort;

  final _eventsController = StreamController<PeerEvent>.broadcast();
  final Map<String, PeerDevice> _known = {};

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  bool _active = false;

  @override
  TransportLayer get layer => TransportLayer.mdns;

  @override
  Stream<PeerEvent> get events => _eventsController.stream;

  @override
  bool get isActive => _active;

  @override
  Future<void> start({required String localDeviceName}) async {
    if (_active) return;

    final service = BonsoirService(
      name: localDeviceName,
      type: serviceType,
      port: transferPort,
    );
    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.ready;
    await _broadcast!.start();

    _discovery = BonsoirDiscovery(type: serviceType);
    await _discovery!.ready;
    _discoverySub = _discovery!.eventStream?.listen(_onDiscoveryEvent);
    await _discovery!.start();

    _active = true;
  }

  void _onDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        // Only the resolved-event variant of BonsoirService carries a host.
        final resolved = event.service;
        if (resolved is! ResolvedBonsoirService) return;
        final host = resolved.host;
        if (host == null) return;
        if (resolved.name == Platform.localHostname) return; // never surface ourselves
        final device = PeerDevice(
          id: 'mdns:${resolved.name}',
          name: resolved.name,
          layer: TransportLayer.mdns,
          lastSeen: DateTime.now(),
          host: host,
          port: resolved.port,
        );
        _known[device.id] = device;
        _eventsController.add(PeerFound(device));
        break;
      case BonsoirDiscoveryEventType.discoveryServiceLost:
        final lost = event.service;
        if (lost == null) return;
        final id = 'mdns:${lost.name}';
        _known.remove(id);
        _eventsController.add(PeerLost(id, TransportLayer.mdns));
        break;
      default:
        break;
    }
  }

  @override
  Future<void> stop() async {
    if (!_active) return;
    await _discoverySub?.cancel();
    await _discovery?.stop();
    await _broadcast?.stop();
    _known.clear();
    _active = false;
  }
}
