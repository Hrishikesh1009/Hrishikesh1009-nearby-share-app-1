/// The connection layer a peer was most recently seen on. Ordered roughly by
/// preference: [nearby] gives the OS-managed high-throughput link, [mdns]
/// falls back to the local router, [ble] is discovery/handshake only and is
/// never used for the file stream itself.
enum TransportLayer { nearby, mdns, ble }

/// A device discovered on any of the three failover layers.
///
/// [id] is layer-relative (endpoint id for Nearby, service name for mDNS,
/// device id for BLE) — it is stable for the lifetime of one advertisement
/// but is not a durable cross-session identity. The "Nearby Devices" /
/// radar screen keys its list off this id.
class PeerDevice {
  const PeerDevice({
    required this.id,
    required this.name,
    required this.layer,
    required this.lastSeen,
    this.host,
    this.port,
    this.nearbyEndpointId,
    this.rssi,
  });

  final String id;
  final String name;
  final TransportLayer layer;
  final DateTime lastSeen;

  /// BLE received-signal-strength, in dBm, when [layer] is
  /// [TransportLayer.ble] (typically -30 to -100; closer to 0 is
  /// stronger). Null for every other layer — the Nearby tab's signal bars
  /// show full strength for those, since an mDNS/Nearby peer is already a
  /// confirmed usable link rather than a distance estimate.
  final int? rssi;

  /// Set when [layer] is [TransportLayer.mdns]: the resolved LAN address to
  /// dial the peer's TCP transfer socket on.
  final String? host;
  final int? port;

  /// Set when [layer] is [TransportLayer.nearby]: the plugin's endpoint id,
  /// used to request a connection through the native Wi-Fi
  /// Direct/Multipeer session before the raw socket is opened.
  final String? nearbyEndpointId;

  /// A small, stable integer derived from [id] so the UI can pick a
  /// deterministic avatar/color per device without needing real artwork.
  int get avatarSeed => id.codeUnits.fold(0, (sum, c) => (sum + c) & 0xFFFF);

  /// 1-3, for the Nearby tab's signal-strength bars. BLE maps [rssi] onto
  /// three rough bands; every other layer reports full strength (see
  /// [rssi]'s doc comment).
  int get signalBars {
    final r = rssi;
    if (r == null) return 3;
    if (r >= -60) return 3;
    if (r >= -80) return 2;
    return 1;
  }

  PeerDevice copyWith({DateTime? lastSeen, String? host, int? port, int? rssi}) {
    return PeerDevice(
      id: id,
      name: name,
      layer: layer,
      lastSeen: lastSeen ?? this.lastSeen,
      host: host ?? this.host,
      port: port ?? this.port,
      nearbyEndpointId: nearbyEndpointId,
      rssi: rssi ?? this.rssi,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PeerDevice && other.id == id && other.layer == layer;

  @override
  int get hashCode => Object.hash(id, layer);

  @override
  String toString() => 'PeerDevice($name, $layer, id=$id)';
}

/// A discovery event as emitted by any [DiscoveryService] implementation.
sealed class PeerEvent {
  const PeerEvent();
}

class PeerFound extends PeerEvent {
  const PeerFound(this.device);
  final PeerDevice device;
}

class PeerLost extends PeerEvent {
  const PeerLost(this.deviceId, this.layer);
  final String deviceId;
  final TransportLayer layer;
}
