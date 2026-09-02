import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Requests every OS-level permission the failover stack needs, in one
/// place, so `NearbyShareEngine` can call [ensureAll] once at startup and
/// individual services never have to guess whether they're authorized.
///
/// iOS local-network (Bonjour) access is prompted automatically by the OS
/// the first time `NSNetServiceBrowser`/`NSNetService` is used — there is
/// no `permission_handler` entry for it, it is driven by the
/// `NSLocalNetworkUsageDescription` + `NSBonjourServices` keys in
/// `ios/Runner/Info.plist` (see that file's comments).
class PermissionService {
  static Future<bool> ensureAll() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        // Android 13+ splits Wi-Fi peer discovery into its own runtime
        // permission distinct from location.
        Permission.nearbyWifiDevices,
        // Still required pre-Android 13 for BLE/Wi-Fi scan results to be
        // populated at all.
        Permission.locationWhenInUse,
      ].request();
      return statuses.values.every((s) => s.isGranted || s.isLimited);
    }

    if (Platform.isIOS) {
      final bluetooth = await Permission.bluetooth.request();
      // Local network access on iOS is requested implicitly by Bonsoir the
      // first time it touches NSNetService; nothing to request here.
      return bluetooth.isGranted;
    }

    // Desktop targets (macOS/Windows/Linux): no runtime permission model
    // for local network/Bluetooth in the same sense; assume granted.
    return true;
  }

  static Future<bool> hasAll() async {
    if (Platform.isAndroid) {
      return (await Permission.bluetoothScan.isGranted) &&
          (await Permission.bluetoothConnect.isGranted) &&
          (await Permission.nearbyWifiDevices.isGranted);
    }
    if (Platform.isIOS) {
      return Permission.bluetooth.isGranted;
    }
    return true;
  }
}
