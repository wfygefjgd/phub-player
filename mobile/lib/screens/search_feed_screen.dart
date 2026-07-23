import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/video_item.dart';
import '../services/mitao_api.dart';
import '../services/phub_api.dart';
import '../services/xvideos_api.dart';
import '../services/app_settings.dart';
import '../services/player_chrome.dart';
import '../utils/http_headers.dart';
import '../utils/playback_helpers.dart';

/// Which backend to use for detail / headers.
enum SearchSource { ph, x, zhong }

/// Vertical swipe player for search results.
/// Single player; preloads next detail; can append pages via [onLoadMore].
class SearchFeedScreen extends StatefulWidget {
  const SearchFeedScreen({
    super.key,
    required this.items,
    required this.source,
    this.initialIndex = 0,
    this.title = '播放',
    this.onLoadMore,
  });

  final List<VideoItem> items;
  final SearchSource source;
  final int initialIndex;
  final String title;
  /// Returns newly appended items (may be empty when no more).
  final Future<List<VideoItem>> Function()? onLoadMore;

  @override
  State<SearchFeedScreen> createState() => _SearchFeedScreenState();
}

class _SearchFeedScreenState extends State<SearchFeedScreen>
    with WidgetsBindingObserver {
  late final PageController _pageCtrl;
  late final List<VideoItem> _items;
  late int _index;
  int _seq = 0;
  int _failStreak = 0;

  VideoPlayerController? _controller;
  bool _pageLoading = false;
  bool _loadingMore = false;
  bool _muted = false;
  bool _seeking = false;
  String _titleText = '';
  String _totalTime = '0:00';
  Timer? _progressTimer;
  final ValueNotifier<double> _slider = ValueNotifier(0);
  final ValueNotifier<String> _curTime = ValueNotifier('0:00');

  final Map<int, VideoDetail> _detailCache = {};
  int? _prefetchingIndex;
  VideoDetail? _currentDetail;

  Map<String, String> get _headers {
    switch (widget.source) {
      case SearchSource.x:
        return {
          ...AppHttpHeaders.browser,
          'Referer': 'https://www.xvideos.com/',
          'Origin': 'https://www.xvideos.com',
        };
      case SearchSource.zhong:
        return {
          ...AppHttpHeaders.browser,
          'Referer': 'https://mitaohk.com/',
          'Origin': 'https://mitaohk.com',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        };
      case SearchSource.ph:
        return AppHttpHeaders.browser;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _muted = context.read<AppSettings>().muted;
    _items = List<VideoItem>.from(widget.items);
    _index = widget.initialIndex.clamp(0, _items.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    _titleText = _items[_index].title;
    WidgetsBinding.instance.addPostFrameCallback((_) => _playIndex(_index));
  }

  @override
  void dispose() {
    try {
      context.read<PlayerChrome>().ensurePortraitChrome();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _slider.dispose();
    _curTime.dispose();
    _pageCtrl.dispose();
    final c = _controller;
    _controller = null;
    try {
      c?.dispose();
    } catch (_) {}
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    await context.read<PlayerChrome>().toggleFullscreen();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller?.pause();
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed) {
      _controller?.play();
      WakelockPlus.enable();
    }
  }

  Future<VideoDetail> _fetchDetail(String url) {
    switch (widget.source) {
      case SearchSource.x:
        return context.read<XvideosApi>().getVideoDetail(url);
      case SearchSource.zhong:
        return context.read<MitaoApi>().getVideoDetail(url);
      case SearchSource.ph:
        return context.read<PhubApi>().getVideoDetail(url);
    }
  }

  Future<void> _ensureMoreIfNearEnd(int page) async {
    if (widget.onLoadMore == null) return;
    if (_loadingMore) return;
    if (page < _items.length - 3) return;
    _loadingMore = true;
    try {
      final extra = await widget.onLoadMore!();
      if (!mounted || extra.isEmpty) return;
      final seen = <String>{for (final e in _items) e.viewkey};
      final add = <VideoItem>[];
      for (final e in extra) {
        if (seen.add(e.viewkey)) add.add(e);
      }
      if (add.isEmpty) return;
      setState(() => _items.addAll(add));
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  void _scheduleSkipToNext(int fromIndex) {
    _failStreak++;
    if (_failStreak > 8) {
      _failStreak = 0;
      return;
    }
    if (mounted) PlaybackHelpers.toast(context, '已跳过无法播放的视频');
    final next = fromIndex + 1;
    Future<void>.delayed(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      if (next >= _items.length) {
        await _ensureMoreIfNearEnd(_items.length - 1);
      }
      if (!mounted) return;
      if (next < _items.length) {
        if (_pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(next);
        } else {
          _playIndex(next);
        }
      }
    });
  }

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _items.length) return;
    final seq = ++_seq;
    final item = _items[index];

    await _disposePlayer();
    if (!mounted || seq != _seq) return;

    setState(() {
      _pageLoading = true;
      _index = index;
      _titleText = item.title;
      _totalTime = '0:00';
    });
    _slider.value = 0;
    _curTime.value = '0:00';

    // Fire load-more early so swipe never dead-ends
    // ignore: unawaited_futures
    _ensureMoreIfNearEnd(index);

    VideoDetail detail;
    try {
      if (_detailCache.containsKey(index)) {
        detail = _detailCache[index]!;
      } else {
        detail = await _fetchDetail(item.url);
        _detailCache[index] = detail;
      }
    } catch (_) {
      if (mounted && seq == _seq) {
        setState(() => _pageLoading = false);
        _scheduleSkipToNext(index);
      }
      return;
    }
    if (!mounted || seq != _seq) return;

    final cap = context.read<AppSettings>().qualityCap;
    final stream = PlaybackHelpers.pickStream(detail, cap) ?? detail.bestStream;
    if (stream == null) {
      setState(() => _pageLoading = false);
      _scheduleSkipToNext(index);
      return;
    }
    _currentDetail = detail;

    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await ctrl.initialize();
    } catch (_) {
      await ctrl.dispose();
      if (mounted && seq == _seq) {
        setState(() => _pageLoading = false);
        _scheduleSkipToNext(index);
      }
      return;
    }
    if (!mounted || seq != _seq) {
      await ctrl.dispose();
      return;
    }

    _failStreak = 0;
    _muted = context.read<AppSettings>().muted;
    ctrl.setVolume(_muted ? 0 : 1);
    final skip = context.read<AppSettings>().skipIntro;
    await PlaybackHelpers.skipIntro(ctrl, enabled: skip);
    if (!mounted || seq != _seq) {
      await ctrl.dispose();
      return;
    }
    _controller = ctrl;
    setState(() {
      _pageLoading = false;
      _titleText = detail.title;
      _totalTime = PlaybackHelpers.fmtDuration(ctrl.value.duration);
    });
    await ctrl.play();
    _startTimer();
    WakelockPlus.enable();
    if (mounted) setState(() {});

    _prefetchDetail(index + 1);
  }

  void _prefetchDetail(int index) {
    if (index < 0 || index >= _items.length) return;
    if (_detailCache.containsKey(index)) return;
    if (_prefetchingIndex == index) return;
    _prefetchingIndex = index;
    final url = _items[index].url;
    _fetchDetail(url).then((d) {
      if (!mounted) return;
      _detailCache[index] = d;
      _detailCache.removeWhere((k, _) => (k - _index).abs() > 2);
    }).catchError((_) {}).whenComplete(() {
      if (_prefetchingIndex == index) _prefetchingIndex = null;
    });
  }

  Future<void> _disposePlayer() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      await c.pause();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  void _startTimer() {
    final ctrl = _controller;
    if (ctrl == null) return;
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!ctrl.value.isInitialized || _seeking) return;
      final pos = ctrl.value.position;
      final dur = ctrl.value.duration;
      if (dur.inMilliseconds <= 0) return;
      _slider.value =
          (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
      _curTime.value = PlaybackHelpers.fmtDuration(pos);
      final t = PlaybackHelpers.fmtDuration(dur);
      if (t != _totalTime && mounted) setState(() => _totalTime = t);
    });
  }

  void _onPageChanged(int page) {
    if (page == _index) return;
    _playIndex(page);
    // ignore: unawaited_futures
    _ensureMoreIfNearEnd(page);
  }

  void _onSeekPreview(double v) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final durMs = c.value.duration.inMilliseconds;
    if (durMs <= 0) return;
    final ms = (durMs * v).round();
    _slider.value = v.clamp(0.0, 1.0);
    _curTime.value = PlaybackHelpers.fmtDuration(Duration(milliseconds: ms));
  }

  Future<void> _onSeekCommit(double v) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      _seeking = false;
      return;
    }
    final durMs = c.value.duration.inMilliseconds;
    if (durMs <= 0) {
      _seeking = false;
      return;
    }
    final target = v.clamp(0.0, 1.0);
    final ms = (durMs * target).round();
    _seeking = true;
    _slider.value = target;
    _curTime.value = PlaybackHelpers.fmtDuration(Duration(milliseconds: ms));
    try {
      await c.seekTo(Duration(milliseconds: ms));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || !identical(c, _controller)) return;
      final p = c.value.position;
      final d = c.value.duration;
      if (d.inMilliseconds > 0) {
        _slider.value = (p.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
        _curTime.value = PlaybackHelpers.fmtDuration(p);
      }
    } catch (_) {
    } finally {
      if (mounted) _seeking = false;
    }
  }

  void _toggleMute() {
    _muted = !_muted;
    _controller?.setVolume(_muted ? 0 : 1);
    context.read<AppSettings>().setMuted(_muted);
    setState(() {});
  }

  void _showQualityPicker() {
    final detail = _currentDetail;
    if (detail == null || detail.streams.isEmpty) return;
    final settings = context.read<AppSettings>();
    final heights = <int>{0};
    for (final s in detail.streams) {
      if (s.height > 0) heights.add(s.height);
    }
    final options = heights.toList()..sort();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('画质', style: TextStyle(color: Colors.white70)),
                dense: true,
              ),
              for (final h in options)
                ListTile(
                  title: Text(
                    h == 0 ? '自动' : '${h}p',
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: settings.qualityCap == h
                      ? const Icon(Icons.check, color: Color(0xFFFF6B35))
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await settings.setQualityCap(h);
                    if (mounted) _playIndex(_index);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final immersive = context.watch<PlayerChrome>().immersive;

    return PopScope(
      canPop: !immersive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && immersive) {
          context.read<PlayerChrome>().exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: immersive
            ? null
            : AppBar(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                elevation: 0,
                title: Text(widget.title, style: const TextStyle(fontSize: 16)),
              ),
        body: GestureDetector(
          onTap: () {
            final c = _controller;
            if (c == null || !c.value.isInitialized) return;
            if (c.value.isPlaying) {
              c.pause();
            } else {
              c.play();
            }
          },
          onLongPressStart: (_) => _controller?.setPlaybackSpeed(3.0),
          onLongPressEnd: (_) => _controller?.setPlaybackSpeed(1.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pageCtrl,
                scrollDirection: Axis.vertical,
                itemCount: _items.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (_, i) {
                  if (i == _index &&
                      _controller != null &&
                      _controller!.value.isInitialized) {
                    return ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
                    );
                  }
                  final thumb = _items[i].thumb;
                  return Container(
                    color: const Color(0xFF1A1A1A),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumb != null && thumb.isNotEmpty)
                          Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            headers: AppHttpHeaders.forMediaUrl(thumb),
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        if (i == _index && _pageLoading)
                          const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF6B35),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              if (immersive)
                Positioned(
                  top: 8,
                  right: 8,
                  child: SafeArea(
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: '退出全屏',
                        icon: const Icon(Icons.fullscreen_exit,
                            color: Colors.white70, size: 22),
                        onPressed: _toggleFullscreen,
                      ),
                    ),
                  ),
                )
              else if (_controller != null || _pageLoading) ...[
                Positioned(
                  left: 12,
                  right: 12,
                  top: 8,
                  child: SafeArea(
                    child: Text(
                      _titleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 4)
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: FeedCircleButton(
                        icon: Icons.fullscreen,
                        onTap: _toggleFullscreen,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 56,
                  child: SafeArea(
                    child: FeedSideControls(
                      muted: _muted,
                      onQuality: _showQualityPicker,
                      onMute: _toggleMute,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    child: FeedProgressBar(
                      slider: _slider,
                      curTime: _curTime,
                      totalTime: _totalTime,
                      onChanged: _onSeekPreview,
                      onChangeStart: (_) {
                        _seeking = true;
                      },
                      onChangeEnd: (v) {
                        // ignore: unawaited_futures
                        _onSeekCommit(v);
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
