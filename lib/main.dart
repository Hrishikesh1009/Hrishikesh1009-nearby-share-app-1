import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/services/nearby_share_engine.dart';

void main() {
  // A hardening measure found by actually running this app (Linux desktop,
  // no D-Bus daemon in the container): some plugins' Linux backends throw
  // synchronously inside a `Stream.listen()` call during subscription
  // setup (`bonsoir`'s Avahi client, `flutter_blue_plus_linux`'s BlueZ
  // client, `network_info_plus`'s NetworkManager client all do this when
  // D-Bus is unreachable) rather than rejecting an awaited `Future`. That
  // bypasses every `try/catch` and `.catchError()` around the call —
  // including the ones already in `AggregatedDiscoveryService.start()` and
  // `WifiShareInfo.currentSsid()` — because the error surfaces via the
  // current zone, not the Future chain. `runZonedGuarded` is the correct
  // backstop for exactly that class of error: it keeps one failing
  // dependency (this happens on real devices too, e.g. Bluetooth genuinely
  // off, or no Wi-Fi hardware) from taking down the whole app.
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(
        ChangeNotifierProvider(
          create: (_) => NearbyShareEngine()..start(),
          child: const NearbyShareApp(),
        ),
      );
    },
    (error, stack) {
      debugPrint('Unhandled zone error (a plugin failed outside its own Future chain): $error');
    },
  );
}
