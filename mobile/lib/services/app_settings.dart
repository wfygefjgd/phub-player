import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/http_client.dart';
import '../utils/system_proxy.dart';

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
  static const _kProxyUserConfigured = 'proxy_user_configured';

  bool _skipIntro = true;
  bool _muted = false;
  int _qualityCap = 0;
  bool _promptOnStall = true;

  /// Follow system proxy when present (default). No hardcoded host/port.
  bool _proxyEnabled = true;
  String _proxyHost = '';
  int _proxyPort = 0;
  String _proxyType = 'http';
  bool _userConfiguredProxy = false;
  bool _ready = false;
  String _proxyAutoNote = '';

  bool get skipIntro => _skipIntro;
  bool get muted => _muted;
  int get qualityCap => _qualityCap;
  bool get promptOnStall => _promptOnStall;
  bool get proxyEnabled => _proxyEnabled;
  String get proxyHost => _proxyHost;
  int get proxyPort => _proxyPort;
  String get proxyType => _proxyType;
  bool get ready => _ready;
  String get proxyAutoNote => _proxyAutoNote;

  bool get hasProxyEndpoint =>
      _proxyHost.isNotEmpty && _proxyPort > 0 && _proxyPort < 65536;

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
    if (!_proxyEnabled) return '关闭（纯直连 / 仅 TUN）';
    if (!hasProxyEndpoint) {
      return '已开启，但未检测到系统代理（将直连；可手动填写）';
    }
    final note = _proxyAutoNote.isEmpty ? '' : ' · $_proxyAutoNote';
    return '${_proxyType.toUpperCase()} $_proxyHost:$_proxyPort$note';
  }

  void _syncHttpClient() {
    // Only enable Dio proxy when we actually have a real endpoint.
    final use = _proxyEnabled && hasProxyEndpoint;
    AppHttpClient.applyProxyConfig(
      enabled: use,
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
      _userConfiguredProxy = p.getBool(_kProxyUserConfigured) ?? false;

      // Prefer "use system proxy when available" by default.
      _proxyEnabled = p.getBool(_kProxyEnabled) ?? true;
      _proxyHost = p.getString(_kProxyHost) ?? '';
      _proxyPort = p.getInt(_kProxyPort) ?? 0;
      _proxyType = p.getString(_kProxyType) ?? 'http';
      if (_proxyType != 'socks5') _proxyType = 'http';
    } catch (_) {
      _skipIntro = true;
      _muted = false;
      _qualityCap = 0;
      _promptOnStall = true;
      _userConfiguredProxy = false;
      _proxyEnabled = true;
      _proxyHost = '';
      _proxyPort = 0;
      _proxyType = 'http';
    }

    if (_userConfiguredProxy && hasProxyEndpoint) {
      _proxyAutoNote = '手动设置';
    } else {
      // Always re-detect on launch unless user fully customized endpoint.
      final detected = await SystemProxy.detect();
      if (detected != null) {
        _proxyHost = detected.host;
        _proxyPort = detected.port;
        _proxyType = detected.type;
        _proxyAutoNote = '系统代理 (${detected.source})';
        // Soft-persist detected values for display; do not mark user-configured.
        try {
          final p = await SharedPreferences.getInstance();
          await p.setString(_kProxyHost, _proxyHost);
          await p.setInt(_kProxyPort, _proxyPort);
          await p.setString(_kProxyType, _proxyType);
          if (!p.containsKey(_kProxyEnabled)) {
            await p.setBool(_kProxyEnabled, true);
          }
        } catch (_) {}
      } else {
        // No system proxy: leave empty → Dio DIRECT (correct for clean devices).
        if (!_userConfiguredProxy) {
          _proxyHost = '';
          _proxyPort = 0;
          _proxyType = 'http';
        }
        _proxyAutoNote = '未检测到系统代理';
      }
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
    final host = v.trim();
    if (host == _proxyHost && _userConfiguredProxy) return;
    _proxyHost = host;
    _userConfiguredProxy = true;
    _proxyAutoNote = '手动设置';
    _syncHttpClient();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kProxyHost, _proxyHost);
      await p.setBool(_kProxyUserConfigured, true);
    } catch (_) {}
  }

  Future<void> setProxyPort(int v) async {
    final port = (v > 0 && v < 65536) ? v : 0;
    if (port == _proxyPort && _userConfiguredProxy) return;
    _proxyPort = port;
    _userConfiguredProxy = true;
    _proxyAutoNote = '手动设置';
    _syncHttpClient();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kProxyPort, _proxyPort);
      await p.setBool(_kProxyUserConfigured, true);
    } catch (_) {}
  }

  Future<void> setProxyType(String v) async {
    final t = v == 'socks5' ? 'socks5' : 'http';
    if (t == _proxyType && _userConfiguredProxy) return;
    _proxyType = t;
    _userConfiguredProxy = true;
    _proxyAutoNote = '手动设置';
    _syncHttpClient();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kProxyType, _proxyType);
      await p.setBool(_kProxyUserConfigured, true);
    } catch (_) {}
  }

  /// Re-read system proxy (e.g. after user enables proxy app).
  Future<void> refreshSystemProxy() async {
    if (_userConfiguredProxy && hasProxyEndpoint) {
      // Keep manual endpoint; still allow re-detect if user wants — caller may clear flag later.
    }
    final detected = await SystemProxy.detect();
    if (detected != null) {
      _proxyHost = detected.host;
      _proxyPort = detected.port;
      _proxyType = detected.type;
      _proxyAutoNote = '系统代理 (${detected.source})';
      _userConfiguredProxy = false;
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_kProxyHost, _proxyHost);
        await p.setInt(_kProxyPort, _proxyPort);
        await p.setString(_kProxyType, _proxyType);
        await p.setBool(_kProxyUserConfigured, false);
      } catch (_) {}
    } else {
      if (!_userConfiguredProxy) {
        _proxyHost = '';
        _proxyPort = 0;
      }
      _proxyAutoNote = '未检测到系统代理';
    }
    _syncHttpClient();
    notifyListeners();
  }
}
