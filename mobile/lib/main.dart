import 'package:flutter/material.dart';

import 'app_player.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings();
  await settings.load();
  runApp(PlayerApp(settings: settings));
}
