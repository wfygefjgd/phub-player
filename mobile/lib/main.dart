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
  // Do NOT lock orientation before runApp — Android 15 + forced-landscape
  // emulators crash if portrait-only is applied during Activity create.
  // Orientation is applied after first frame in [PhubApp].
  final settings = AppSettings();
  await settings.load();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // After first frame only — safe on Android 12–15
      PlayerChrome.applyAllOrientations();
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ));
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
