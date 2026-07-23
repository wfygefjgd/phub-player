import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phub_player/privacy_browser/privacy_browser_shell.dart';
import 'package:phub_player/privacy_browser/tab_manager.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Privacy browser shell builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => TabManager(maxTabs: 3),
        child: const MaterialApp(home: PrivacyBrowserShell()),
      ),
    );
    await tester.pump();
    expect(find.text('搜索或输入网址'), findsOneWidget);
    expect(find.byTooltip('重置浏览器'), findsOneWidget);
  });
}
