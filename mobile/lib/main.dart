import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'services/app_settings.dart';
import 'services/mitao_api.dart';
import 'services/phub_api.dart';
import 'services/player_chrome.dart';
import 'services/translator.dart';
import 'services/xvideos_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No orientation / SystemUI calls before runApp — Android 15 can crash
  // when the Activity is still creating under forced landscape.
  final settings = AppSettings();
  try {
    await settings.load();
  } catch (_) {}
  runApp(PhubApp(settings: settings));
}

class PhubApp extends StatefulWidget {
  const PhubApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<PhubApp> createState() => _PhubAppState();
}

class _PhubAppState extends State<PhubApp> {
  @override
  void initState() {
    super.initState();
    // Defer chrome until UI is up (avoids A15 startup races).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        PlayerChrome.applyAllOrientations();
        try {
          SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarIconBrightness: Brightness.light,
          ));
        } catch (_) {}
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => PhubApi()),
        Provider(create: (_) => XvideosApi()),
        Provider(create: (_) => MitaoApi()),
        Provider(create: (_) => Translator()),
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider(create: (_) => PlayerChrome()),
      ],
      child: MaterialApp(
        title: 'PHUB Player',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFF6B35),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E1E1E),
            foregroundColor: Colors.white,
          ),
        ),
        home: const HomeShell(),
      ),
    );
  }
}
