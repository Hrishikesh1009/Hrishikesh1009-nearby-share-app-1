import 'package:network_info_plus/network_info_plus.dart';

/// Real WiFi network info for the "Share Your WiFi" tab.
///
/// Platform honesty note: neither Android nor iOS lets a normal app read
/// the network's actual PSK — there is no public API for it, by design.
/// So the QR this tab generates encodes the SSID we *can* read plus a
/// password the user sets in Settings for guests to use
/// (`AppSettingsStore.wifiSharePassword`), not the router's real password.
/// "Personal Hotspot" likewise can't be toggled programmatically by a
/// third-party app on either platform; see `features/wifi/wifi_tab.dart`
/// for how the toggle is handled honestly instead of faked.
class WifiShareInfo {
  static final NetworkInfo _networkInfo = NetworkInfo();

  static Future<String> currentSsid() async {
    try {
      final ssid = await _networkInfo.getWifiName();
      if (ssid == null || ssid.isEmpty) return 'Not connected';
      return ssid.replaceAll('"', ''); // Android/iOS sometimes quote it
    } catch (_) {
      return 'Not connected';
    }
  }

  /// Standard `WIFI:` QR payload — recognized by both platforms' native
  /// camera "join network" prompt.
  static String qrPayload({required String ssid, required String password}) {
    String esc(String s) =>
        s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(':', r'\:').replaceAll(',', r'\,');
    return 'WIFI:S:${esc(ssid)};T:WPA;P:${esc(password)};;';
  }
}
