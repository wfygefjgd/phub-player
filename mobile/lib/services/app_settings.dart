import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight user prefs.
class AppSettings extends ChangeNotifier {
  static const _kSkipIntro = 'skip_intro_10s';
  static const _kMuted = 'playback_muted';
  static const _kQualityCap = 'quality_cap_height'; // 0=auto preferred
  static const _kPromptOnStall = 'prompt_on_stall';

  bool _skipIntro = true;
  bool _muted = false;
  /// 0 = auto (<=720 preferred); else max height 360/480/720/1080
  int _qualityCap = 0;
  bool _promptOnStall = true;
  bool _ready = false;

  bool get skipIntro => _skipIntro;
  bool get muted => _muted;
  int get qualityCap => _qualityCap;
  bool get promptOnStall => _promptOnStall;
  bool get ready => _ready;

  String get qualityLabel {
    switch (_qualityCap) {
      case 360:
        return '360p';
      case 480:
        return '480p';
      case 720:
        return '720p';
      case 1080:
        return '1080p';
      default:
        return '自动';
    }
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _skipIntro = p.getBool(_kSkipIntro) ?? true;
      _muted = p.getBool(_kMuted) ?? false;
      _qualityCap = p.getInt(_kQualityCap) ?? 0;
      _promptOnStall = p.getBool(_kPromptOnStall) ?? true;
    } catch (_) {
      _skipIntro = true;
      _muted = false;
      _qualityCap = 0;
      _promptOnStall = true;
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

  Future<void> setMuted(bool v) async {
    if (_muted == v) return;
    _muted = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kMuted, v);
    } catch (_) {}
  }

  Future<void> setQualityCap(int v) async {
    if (_qualityCap == v) return;
    _qualityCap = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kQualityCap, v);
    } catch (_) {}
  }

  Future<void> setPromptOnStall(bool v) async {
    if (_promptOnStall == v) return;
    _promptOnStall = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kPromptOnStall, v);
    } catch (_) {}
  }
}
