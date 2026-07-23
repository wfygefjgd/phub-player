import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Global chrome: hide bottom tabs / settings when immersive fullscreen.
class PlayerChrome extends ChangeNotifier {
  bool _immersive = false;

  bool get immersive => _immersive;

  Future<void> enterFullscreen() async {
    if (_immersive) return;
    _immersive = true;
    notifyListeners();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> exitFullscreen() async {
    if (!_immersive) return;
    _immersive = false;
    notifyListeners();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> toggleFullscreen() async {
    if (_immersive) {
      await exitFullscreen();
    } else {
      await enterFullscreen();
    }
  }

  /// Call from dispose of feed screens to avoid stuck landscape.
  Future<void> ensurePortraitChrome() async {
    if (_immersive) {
      await exitFullscreen();
    }
  }
}
