import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'services/app_settings.dart';
import 'services/mitao_api.dart';
import 'services/phub_api.dart';
import 'services/player_chrome.dart';
import 'services/translator.dart';
import 'services/xvideos_api.dart';

/// Video player shell (feeds + search). No launch wipe.
class PlayerApp extends StatelessWidget {
  const PlayerApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider(create: (_) => PlayerChrome()),
        Provider(create: (_) => PhubApi()),
        Provider(create: (_) => XvideosApi()),
        Provider(create: (_) => MitaoApi()),
        Provider(create: (_) => Translator()),
      ],
      child: MaterialApp(
        title: 'PHUB Player',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF1E1E1E),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF6B35),
            secondary: Color(0xFFFF6B35),
            surface: Color(0xFF1E1E1E),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E1E1E),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        home: const HomeShell(),
      ),
    );
  }
}
