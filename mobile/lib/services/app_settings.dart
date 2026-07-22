import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight user prefs (skip intro, etc.).
class AppSettings extends ChangeNotifier {
  static const _kSkipIntro = 'skip_intro_10s';

  bool _skipIntro = true;
  bool _ready = false;

  bool get skipIntro => _skipIntro;
  bool get ready => _ready;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _skipIntro = p.getBool(_kSkipIntro) ?? true;
    } catch (_) {
      _skipIntro = true;
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> setSkipIntro(bool v) async {
    if (_skipIntro == v) return;
    _skipIntro = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kSkipIntro, v);
    } catch (_) {}
  }
}
