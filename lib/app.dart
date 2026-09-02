import 'package:flutter/material.dart';

import 'features/shell/app_shell.dart';
import 'theme/design_tokens.dart';

class NearbyShareApp extends StatelessWidget {
  const NearbyShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nearby Share',
      debugShowCheckedModeBanner: false,
      // The design's font stack (`-apple-system`/`SF Pro Rounded` on iOS,
      // `Segoe UI Rounded`/Roboto elsewhere) is each platform's own system
      // font, which is exactly what Flutter's default (unset) fontFamily
      // already renders with per-platform — no bundled font needed.
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.screenBg,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.blue, brightness: Brightness.light),
        textTheme: Typography.material2021().black.apply(
              bodyColor: AppColors.ink,
              displayColor: AppColors.ink,
            ),
      ),
      home: const AppShell(),
    );
  }
}
