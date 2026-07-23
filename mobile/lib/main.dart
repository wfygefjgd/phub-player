import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_player.dart';
import 'privacy_browser/privacy_browser_shell.dart';
import 'privacy_browser/privacy_engine.dart';
import 'services/app_mode.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(false);
  }

  final mode = await AppModeStore.load();

  // Full wipe only for privacy-browser product path.
  if (mode == AppMode.browser) {
    await PrivacyEngine.wipeOnLaunch();
    runApp(const PrivacyBrowserApp());
    return;
  }

  final settings = AppSettings();
  await settings.load();
  runApp(PlayerApp(settings: settings));
}
