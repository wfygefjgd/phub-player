import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/video_item.dart';

/// Shared playback helpers for feed / search-feed.
class PlaybackHelpers {
  /// Skip ~15s intro ads when [enabled]. Short clips stay near start.
  static Future<void> skipIntro(
    VideoPlayerController ctrl, {
    bool enabled = true,
  }) async {
    if (!enabled || !ctrl.value.isInitialized) return;
    final dur = ctrl.value.duration;
    final total = dur.inSeconds;
    if (total <= 20) return;
    // Prefer 15s; leave at least 5s of content
    final targetSec = total <= 25 ? 8 : 15;
    if (total - targetSec < 5) return;
    try {
      await ctrl.seekTo(Duration(seconds: targetSec));
    } catch (_) {}
  }

  static StreamQuality? pickStream(VideoDetail detail, int qualityCap) =>
      detail.streamForCap(qualityCap);

  /// Ordered candidates for init fallback: preferred/cap first, then lower, then higher.
  static List<StreamQuality> streamCandidates(
    VideoDetail detail,
    int qualityCap,
  ) {
    if (detail.streams.isEmpty) return const [];
    final primary = detail.streamForCap(qualityCap);
    final rest = [...detail.streams]
      ..sort((a, b) => b.pixels.compareTo(a.pixels));
    final out = <StreamQuality>[];
    final seen = <String>{};
    void add(StreamQuality? s) {
      if (s == null || s.url.isEmpty) return;
      if (seen.add(s.url)) out.add(s);
    }

    add(primary);
    // Lower first (more likely to play on weak net), then any remaining.
    final lower = rest
        .where((s) =>
            primary == null || s.height <= 0 || s.height < primary.height)
        .toList()
      ..sort((a, b) => b.pixels.compareTo(a.pixels));
    for (final s in lower) {
      add(s);
    }
    for (final s in rest) {
      add(s);
    }
    return out;
  }

  /// Brief non-blocking toast.
  static void toast(
    BuildContext context,
    String msg, {
    Duration duration = const Duration(milliseconds: 1200),
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        margin: const EdgeInsets.fromLTRB(48, 0, 48, 72),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  /// Map raw exceptions to short Chinese hints (keep original if unknown).
  static String friendlyError(Object error) {
    final s = error.toString();
    final low = s.toLowerCase();
    if (s.contains('PhubException:')) {
      return s.replaceFirst('PhubException: ', '');
    }
    if (low.contains('403') || low.contains('forbidden')) {
      return '访问被拒绝(403)，请检查 VPN / 网络';
    }
    if (low.contains('404') || low.contains('not found')) {
      return '内容不存在(404)';
    }
    if (low.contains('timeout') || low.contains('timed out')) {
      return '网络超时，请稍后重试';
    }
    if (low.contains('socket') ||
        low.contains('connection') ||
        low.contains('network') ||
        low.contains('failed host lookup') ||
        low.contains('connection refused')) {
      return '网络异常，请检查 VPN 是否开启';
    }
    if (low.contains('handshake') || low.contains('certificate')) {
      return '安全连接失败，请检查网络环境';
    }
    if (s.length > 80) return '${s.substring(0, 80)}…';
    return s;
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

/// Circular side control — fixed size so a column of buttons shares one center line.
class FeedCircleButton extends StatelessWidget {
  const FeedCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  static const double box = 48;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: box,
      height: box,
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Icon(icon, color: Colors.white, size: size),
          ),
        ),
      ),
    );
  }
}

/// Right-side control: mute only (quality lives in top-right settings).
/// Fullscreen lives under the title on the left.
class FeedSideControls extends StatelessWidget {
  const FeedSideControls({
    super.key,
    required this.muted,
    required this.onMute,
  });

  final bool muted;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    return FeedCircleButton(
      icon: muted ? Icons.volume_off : Icons.volume_up,
      onTap: onMute,
      size: 24,
    );
  }
}

/// Bottom seek bar; drag only updates UI — parent seeks on [onChangeEnd].
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
      height: 48,
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
              data: SliderThemeData(
                trackHeight: 3.5,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: const Color(0xFFFF6B35),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFFF6B35),
                // Smoother visual while dragging
                trackShape: const RoundedRectSliderTrackShape(),
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
