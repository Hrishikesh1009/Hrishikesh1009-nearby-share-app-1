import 'dart:async';

import '../models/peer_device.dart';
import 'discovery_service.dart';

/// Layer 1: the OS-managed local link — Wi-Fi Direct + Bluetooth via
/// Google's Nearby Connections API on Android, Multipeer Connectivity on
/// iOS. This is the preferred layer when present: the OS negotiates the
/// fastest available radio for us.
///
/// **Currently a documented no-op**, not a real implementation. This
/// repo originally depended on `flutter_nearby_connections` here, but its
/// Android build script calls the long-removed Gradle `jcenter()`
/// repository and fails outright against the AGP version current Flutter
/// releases require — the package hasn't been updated since December 2023
/// and is incompatible with a modern toolchain. Rather than ship a build
/// that doesn't compile, this layer stands down cleanly (`isActive` stays
/// false, `start`/`stop` are no-ops, it never emits a [PeerEvent]) so the
/// app runs correctly on Layer 2 (`MdnsDiscoveryService`) and Layer 3
/// (`BleDiscoveryService`) alone — exactly the "layers fail independently"
/// design `AggregatedDiscoveryService` already has, just permanently
/// applied to this one instead of per-run.
///
/// To restore this layer, swap in a maintained alternative — as of this
/// writing `flutter_p2p_connection` (Wi-Fi Direct, Android) and
/// `nearby_connections` (Google Nearby Connections, Android) are both
/// actively published; neither is a drop-in API match for the shape below,
/// so re-verify against a real build (`flutter build apk`) before trusting
/// it, the same way this file's predecessor should have been.
class NearbyDiscoveryService implements DiscoveryService {
  final _eventsController = StreamController<PeerEvent>.broadcast();

  @override
  TransportLayer get layer => TransportLayer.nearby;

  @override
  Stream<PeerEvent> get events => _eventsController.stream;

  @override
  bool get isActive => false;

  @override
  Future<void> start({required String localDeviceName}) async {}

  @override
  Future<void> stop() async {}
}
