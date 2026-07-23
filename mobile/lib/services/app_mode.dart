import 'package:shared_preferences/shared_preferences.dart';

/// App product mode: video player (default) vs privacy browser.
enum AppMode {
  player,
  browser,
}

class AppModeStore {
  static const _key = 'app_launch_mode_v1';

  static Future<AppMode> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == 'browser') return AppMode.browser;
    } catch (_) {}
    return AppMode.player;
  }

  static Future<void> save(AppMode mode) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key,
        mode == AppMode.browser ? 'browser' : 'player',
      );
    } catch (_) {}
  }
}
