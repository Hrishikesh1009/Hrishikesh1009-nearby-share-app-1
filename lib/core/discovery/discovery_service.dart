import '../models/peer_device.dart';

/// Common shape for every discovery layer. Implementations advertise this
/// device and browse for others concurrently; [events] emits [PeerFound]
/// / [PeerLost] as peers come and go so the "Nearby Devices" / radar screen
/// can animate them in and out live rather than polling.
abstract class DiscoveryService {
  TransportLayer get layer;

  Stream<PeerEvent> get events;

  /// True once [start] has completed and the layer is actively
  /// broadcasting + browsing.
  bool get isActive;

  Future<void> start({required String localDeviceName});
  Future<void> stop();
}
