import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'services/download_service.dart';
import 'services/phub_api.dart';
import 'services/translator.dart';
import 'services/xvideos_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PhubApp());
}

class PhubApp extends StatelessWidget {
  const PhubApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ios = !kIsWeb && Platform.isIOS;
    return MultiProvider(
      providers: [
        Provider(create: (_) => PhubApi()),
        Provider(create: (_) => XvideosApi()),
        Provider(create: (_) => Translator()),
        // Downloads only on Android (iOS build strips download UI)
        if (!ios) ChangeNotifierProvider(create: (_) => DownloadService()),
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
