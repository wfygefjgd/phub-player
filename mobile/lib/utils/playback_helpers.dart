import 'package:video_player/video_player.dart';

/// Shared playback helpers for feed / search-feed.
class PlaybackHelpers {
  /// Skip ~10s intro ads. Short clips (<=15s) stay at 0.
  static Future<void> skipIntro(VideoPlayerController ctrl) async {
    if (!ctrl.value.isInitialized) return;
    final dur = ctrl.value.duration;
    if (dur.inSeconds <= 15) return;
    final targetSec = dur.inSeconds <= 20 ? 5 : 10;
    final remain = dur.inSeconds - targetSec;
    if (remain < 3) return;
    try {
      await ctrl.seekTo(Duration(seconds: targetSec));
    } catch (_) {}
  }
}
