import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phub_player/main.dart';
import 'package:phub_player/services/app_settings.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    final settings = AppSettings();
    await tester.pumpWidget(PhubApp(settings: settings));
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
