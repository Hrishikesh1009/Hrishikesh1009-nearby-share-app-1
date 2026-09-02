import 'package:shared_preferences/shared_preferences.dart';

/// Persisted device name + feature toggles for the Settings tab — real,
/// disk-backed state (the design's reference script keeps this in memory
/// only, reset on every reload).
class AppSettingsStore {
  AppSettingsStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettingsStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettingsStore._(prefs);
  }

  static const _kDeviceName = 'device_name';
  static const _kSmartTransfer = 'smart_transfer';
  static const _kNotifications = 'notifications_enabled';
  static const _kDiscoverable = 'discoverable';
  static const _kWifiSharePassword = 'wifi_share_password';

  String get deviceName => _prefs.getString(_kDeviceName) ?? 'My Phone';
  Future<void> setDeviceName(String value) => _prefs.setString(_kDeviceName, value);

  /// When on, prefer the BLE-finds/Wi-Fi-Direct-moves handoff the Nearby
  /// tab's banner describes. BLE stays discovery/handshake-only either way
  /// (see `core/discovery/ble_discovery_service.dart`) — this only
  /// influences which data-plane layer `NearbyShareEngine` prefers when
  /// more than one is available for the same peer.
  bool get smartTransferEnabled => _prefs.getBool(_kSmartTransfer) ?? true;
  Future<void> setSmartTransferEnabled(bool value) => _prefs.setBool(_kSmartTransfer, value);

  bool get notificationsEnabled => _prefs.getBool(_kNotifications) ?? true;
  Future<void> setNotificationsEnabled(bool value) => _prefs.setBool(_kNotifications, value);

  /// Whether this device answers other devices' discovery browses at all.
  bool get discoverable => _prefs.getBool(_kDiscoverable) ?? true;
  Future<void> setDiscoverable(bool value) => _prefs.setBool(_kDiscoverable, value);

  /// The password encoded into the WiFi tab's join QR. Neither Android nor
  /// iOS lets an app read the network's actual PSK back from the OS — this
  /// is a password the user sets *for guests to use*, not the router's
  /// real one. See `core/wifi/wifi_share_info.dart`.
  String get wifiSharePassword => _prefs.getString(_kWifiSharePassword) ?? 'cloudkey482';
  Future<void> setWifiSharePassword(String value) => _prefs.setString(_kWifiSharePassword, value);

  static const _kPairedDevices = 'paired_ble_devices';

  /// Devices the user tapped "Pair" on, on the Bluetooth tab. This is an
  /// app-local convenience list, not a real OS Bluetooth pairing — a
  /// sandboxed app cannot initiate a genuine BT pairing/bonding, only see
  /// BLE advertisements (see `core/discovery/ble_discovery_service.dart`)
  /// and remember which of them the user cares about.
  List<String> get pairedDeviceNames => _prefs.getStringList(_kPairedDevices) ?? const [];
  Future<void> setPairedDeviceNames(List<String> names) =>
      _prefs.setStringList(_kPairedDevices, names);
}
