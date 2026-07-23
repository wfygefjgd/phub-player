import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Global chrome: hide bottom tabs / settings when immersive fullscreen.
///
/// Android 15 notes:
/// - Never call setPreferredOrientations during Activity create (before first frame).
/// - Never lock to portrait-only: forced-landscape emulators will crash.
/// - Fullscreen prefers landscape but still allows all as fallback if set fails.
class PlayerChrome extends ChangeNotifier {
  bool _immersive = false;

  bool get immersive => _immersive;

  /// Allow every orientation (safe default for Android 12–15).
  static Future<void> applyAllOrientations() async {
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
  }

  /// @deprecated use [applyAllOrientations]
  static Future<void> applyPortraitPreferred() => applyAllOrientations();

  static Future<void> applyLandscapePreferred() async {
    try {
      // Prefer landscape for immersive video, but keep portrait as escape hatch
      // so Android 15 / multi-window cannot force a crash.
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (_) {
      await applyAllOrientations();
    }
  }

  Future<void> enterFullscreen() async {
    if (_immersive) return;
    _immersive = true;
    notifyListeners();
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {
      try {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: const [],
        );
      } catch (_) {}
    }
    await applyLandscapePreferred();
  }

  Future<void> exitFullscreen() async {
    if (!_immersive) return;
    _immersive = false;
    notifyListeners();
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      try {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      } catch (_) {}
    }
    await applyAllOrientations();
  }

  Future<void> toggleFullscreen() async {
    if (_immersive) {
      await exitFullscreen();
    } else {
      await enterFullscreen();
    }
  }

  /// Call from dispose of feed screens to avoid stuck landscape UI chrome.
  Future<void> ensurePortraitChrome() async {
    if (_immersive) {
      await exitFullscreen();
    }
  }
}
