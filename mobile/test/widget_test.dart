import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phub_player/main.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PhubApp());
    await tester.pump();

    // Verify app shell renders
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}