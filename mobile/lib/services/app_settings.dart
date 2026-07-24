import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/http_client.dart';

/// Lightweight user prefs.
class AppSettings extends ChangeNotifier {
  static const _kSkipIntro = 'skip_intro_10s';
  static const _kMuted = 'playback_muted';
  static const _kQualityCap = 'quality_cap_height'; // 0=auto preferred
  static const _kPromptOnStall = 'prompt_on_stall';
  static const _kProxyEnabled = 'proxy_enabled';
  static const _kProxyHost = 'proxy_host';
  static const _kProxyPort = 'proxy_port';
  static const _kProxyType = 'proxy_type'; // http | socks5

  bool _skipIntro = true;
  bool _muted = false;
  /// 0 = auto (<=720 preferred); else max height 360/480/720/1080
  int _qualityCap = 0;
  bool _promptOnStall = true;
  bool _proxyEnabled = false;
  String _proxyHost = '10.0.2.2';
  int _proxyPort = 7890;
  String _proxyType = 'http';
  bool _ready = false;

  bool get skipIntro => _skipIntro;
  bool get muted => _muted;
  int get qualityCap => _qualityCap;
  bool get promptOnStall => _promptOnStall;
  bool get proxyEnabled => _proxyEnabled;
  String get proxyHost => _proxyHost;
  int get proxyPort => _proxyPort;
  String get proxyType => _proxyType;
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

  String get proxySummary {
    if (!_proxyEnabled) return '关闭（系统直连 / TUN）';
    return '${_proxyType.toUpperCase()} $_proxyHost:$_proxyPort';
  }

  void _syncHttpClient() {
    AppHttpClient.applyProxyConfig(
      enabled: _proxyEnabled,
      host: _proxyHost,
      port: _proxyPort,
      type: _proxyType,
    );
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _skipIntro = p.getBool(_kSkipIntro) ?? true;
      _muted = p.getBool(_kMuted) ?? false;
      _qualityCap = p.getInt(_kQualityCap) ?? 0;
      _promptOnStall = p.getBool(_kPromptOnStall) ?? true;
      _proxyEnabled = p.getBool(_kProxyEnabled) ?? false;
      _proxyHost = p.getString(_kProxyHost) ?? '10.0.2.2';
      _proxyPort = p.getInt(_kProxyPort) ?? 7890;
      _proxyType = p.getString(_kProxyType) ?? 'http';
      if (_proxyType != 'socks5') _proxyType = 'http';
    } catch (_) {
      _skipIntro = true;
      _muted = false;
      _qualityCap = 0;
      _promptOnStall = true;
      _proxyEnabled = false;
      _proxyHost = '10.0.2.2';
      _proxyPort = 7890;
      _proxyType = 'http';
    }
    _syncHttpClient();
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

  Future<void> setProxyEnabled(bool v) async {
    if (_proxyEnabled == v) return;
    _proxyEnabled = v;
    _syncHttpClient();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kProxyEnabled, v);
    } catch (_) {}
  }

  Future<void> setProxyHost(String v) async {
    final t = v.trim();
    if (t == _proxyHost) return;
    _proxyHost = t.isEmpty ? '10.0.2.2' : t;
    _syncHttpClient();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kProxyHost, _proxyHost);
    } catch (_) {}
  }

  Future<void> setProxyPort(int v) async {
    final port = (v > 0 && v < 65536) ? v : 7890;
    if (port == _proxyPort) return;
    _proxyPort = port;
    _syncHttpClient();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kProxyPort, _proxyPort);
    } catch (_) {}
  }

  Future<void> setProxyType(String v) async {
    final t = v == 'socks5' ? 'socks5' : 'http';
    if (t == _proxyType) return;
    _proxyType = t;
    _syncHttpClient();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kProxyType, _proxyType);
    } catch (_) {}
  }
}
