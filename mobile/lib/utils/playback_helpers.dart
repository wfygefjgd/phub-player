import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/video_item.dart';

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

  static StreamQuality? pickStream(VideoDetail detail, int qualityCap) =>
      detail.streamForCap(qualityCap);

  /// Brief non-blocking toast.
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

  static String fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Circular mute control used on feeds.
class FeedMuteButton extends StatelessWidget {
  const FeedMuteButton({
    super.key,
    required this.muted,
    required this.onTap,
  });

  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            muted ? Icons.volume_off : Icons.volume_up,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// Bottom seek bar; [dragging] freezes external progress updates.
class FeedProgressBar extends StatelessWidget {
  const FeedProgressBar({
    super.key,
    required this.slider,
    required this.curTime,
    required this.totalTime,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final ValueNotifier<double> slider;
  final ValueNotifier<String> curTime;
  final String totalTime;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          ValueListenableBuilder<String>(
            valueListenable: curTime,
            builder: (_, t, __) => Text(
              t,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 2,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Color(0xFFFF6B35),
                inactiveTrackColor: Colors.white24,
                thumbColor: Color(0xFFFF6B35),
              ),
              child: ValueListenableBuilder<double>(
                valueListenable: slider,
                builder: (_, v, __) => Slider(
                  value: v.clamp(0.0, 1.0),
                  onChanged: onChanged,
                  onChangeStart: onChangeStart,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
          ),
          Text(
            totalTime,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
