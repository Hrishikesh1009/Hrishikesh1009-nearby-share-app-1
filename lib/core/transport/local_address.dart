import 'dart:io';

/// Best-effort discovery of a LAN-reachable IPv4 address for this device.
///
/// Used to hand our transfer-server's host:port to a peer that found us
/// over Layer 1 (Nearby Connections/Multipeer): once that OS-managed
/// session is up, both devices are joined to a shared network segment
/// (a Wi-Fi Direct group or a Multipeer-bridged link), and we dial our
/// *own* raw `Socket` on it rather than pushing file bytes through the
/// plugin's own message channel — see `core/transport/transfer_client.dart`.
class LocalAddress {
  static Future<InternetAddress?> discover() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    if (interfaces.isEmpty) return null;

    // Android names a Wi-Fi Direct group interface e.g. "p2p-wlan0-0";
    // prefer it when present since it's the interface the peer actually
    // formed a link on.
    final wifiDirect = interfaces.where((i) => i.name.contains('p2p'));
    final chosen = wifiDirect.isNotEmpty ? wifiDirect.first : interfaces.first;
    return chosen.addresses.isNotEmpty ? chosen.addresses.first : null;
  }
}
