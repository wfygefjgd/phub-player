import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'privacy_browser/privacy_browser_shell.dart';
import 'privacy_browser/privacy_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(false);
  }

  await PrivacyEngine.wipeOnLaunch();
  runApp(const PrivacyBrowserApp());
}
