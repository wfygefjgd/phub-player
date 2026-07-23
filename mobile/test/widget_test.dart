import 'package:flutter_test/flutter_test.dart';
import 'package:phub_player/app_player.dart';
import 'package:phub_player/services/app_settings.dart';

void main() {
  testWidgets('Player app builds', (WidgetTester tester) async {
    final settings = AppSettings();
    await tester.pumpWidget(PlayerApp(settings: settings));
    await tester.pump();
    // Bottom nav labels
    expect(find.text('热'), findsOneWidget);
  });
}
