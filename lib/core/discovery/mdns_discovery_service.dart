import 'dart:async';

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

  /// The port `core/transport/` is listening on, advertised via mDNS.
  final int transferPort;

  final _eventsController = StreamController<PeerEvent>.broadcast();
  final Map<String, PeerDevice> _known = {};

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  String? _advertisedName;
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
    _advertisedName = localDeviceName;

    final service = BonsoirService(name: localDeviceName, type: serviceType, port: transferPort);
    final broadcast = BonsoirBroadcast(service: service);
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;

    final discovery = BonsoirDiscovery(type: serviceType);
    await discovery.initialize();
    // Must listen before start(): events (including the ones that arrive
    // as part of starting) are only delivered to subscribers already
    // attached to `eventStream`.
    _discoverySub = discovery.eventStream?.listen((event) => _onDiscoveryEvent(event, discovery));
    await discovery.start();
    _discovery = discovery;

    _active = true;
  }

  void _onDiscoveryEvent(BonsoirDiscoveryEvent event, BonsoirDiscovery discovery) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        // Found isn't resolved yet — hostAddresses is still empty. Kick off
        // resolution; the actual address arrives via a Resolved event below.
        unawaited(event.service.resolve(discovery.serviceResolver));
      case BonsoirDiscoveryServiceResolvedEvent():
        _upsert(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        _upsert(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        final id = 'mdns:${event.service.name}';
        _known.remove(id);
        _eventsController.add(PeerLost(id, TransportLayer.mdns));
      default:
        break;
    }
  }

  void _upsert(BonsoirService service) {
    if (service.name == _advertisedName) return; // never surface ourselves
    final host = service.hostAddress;
    if (host == null) return;

    final device = PeerDevice(
      id: 'mdns:${service.name}',
      name: service.name,
      layer: TransportLayer.mdns,
      lastSeen: DateTime.now(),
      host: host,
      port: service.port,
    );
    _known[device.id] = device;
    _eventsController.add(PeerFound(device));
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
