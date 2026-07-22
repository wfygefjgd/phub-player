import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Shared playback helpers for feed / search-feed.
class PlaybackHelpers {
  /// Skip ~10s intro ads when [enabled]. Short clips (<=15s) stay at 0.
  static Future<void> skipIntro(
    VideoPlayerController ctrl, {
    bool enabled = true,
  }) async {
    if (!enabled || !ctrl.value.isInitialized) return;
    final dur = ctrl.value.duration;
    if (dur.inSeconds <= 15) return;
    final targetSec = dur.inSeconds <= 20 ? 5 : 10;
    final remain = dur.inSeconds - targetSec;
    if (remain < 3) return;
    try {
      await ctrl.seekTo(Duration(seconds: targetSec));
    } catch (_) {}
  }

  /// Brief non-blocking toast (auto-skip failed video, etc.).
  static void toast(BuildContext context, String msg) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        margin: const EdgeInsets.fromLTRB(48, 0, 48, 72),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }
}
