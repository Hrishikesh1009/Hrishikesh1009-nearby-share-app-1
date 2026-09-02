import 'package:flutter/material.dart';

import 'features/discovery/discovery_screen.dart';

class NearbyShareApp extends StatelessWidget {
  const NearbyShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nearby Share',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3B82F6),
        brightness: Brightness.dark,
      ),
      home: const DiscoveryScreen(),
    );
  }
}
