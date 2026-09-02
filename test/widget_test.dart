// A minimal smoke test: the app shell renders its loading state before
// `NearbyShareEngine.start()` (which does real socket/permission/prefs
// I/O) resolves, without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nearby_share/app.dart';
import 'package:nearby_share/core/services/nearby_share_engine.dart';

void main() {
  testWidgets('shows a loading indicator before the engine is ready', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NearbyShareEngine(),
        child: const NearbyShareApp(),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
