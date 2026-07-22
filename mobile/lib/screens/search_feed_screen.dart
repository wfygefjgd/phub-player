import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/video_item.dart';
import '../services/mitao_api.dart';
import '../services/phub_api.dart';
import '../services/xvideos_api.dart';
import '../utils/http_headers.dart';

/// Which backend to use for detail / headers.
enum SearchSource { ph, x, zhong }

/// Vertical swipe player for a fixed search-result list.
/// Single ExoPlayer/AVPlayer instance; preloads **next video detail** only.
class SearchFeedScreen extends StatefulWidget {
  const SearchFeedScreen({
    super.key,
    required this.items,
    required this.source,
    this.initialIndex = 0,
    this.title = '播放',
  });

  final List<VideoItem> items;
  final SearchSource source;
  final int initialIndex;
  final String title;

  @override
  State<SearchFeedScreen> createState() => _SearchFeedScreenState();
}

class _SearchFeedScreenState extends State<SearchFeedScreen>
    with WidgetsBindingObserver {
  late final PageController _pageCtrl;
  late int _index;
  int _seq = 0;

  VideoPlayerController? _controller;
  bool _pageLoading = false;
  bool _muted = false;
  String _titleText = '';
  String _totalTime = '0:00';
  Timer? _progressTimer;
  final ValueNotifier<double> _slider = ValueNotifier(0);
  final ValueNotifier<String> _curTime = ValueNotifier('0:00');

  /// Pre-fetched next detail for seamless switch
  final Map<int, VideoDetail> _detailCache = {};
  int? _prefetchingIndex;

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
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    _titleText = widget.items[_index].title;
    WidgetsBinding.instance.addPostFrameCallback((_) => _playIndex(_index));
  }

  @override
  void dispose() {
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

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= widget.items.length) return;
    final seq = ++_seq;
    final item = widget.items[index];

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

    VideoDetail detail;
    try {
      if (_detailCache.containsKey(index)) {
        detail = _detailCache[index]!;
      } else {
        detail = await _fetchDetail(item.url);
        _detailCache[index] = detail;
      }
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _pageLoading = false);
      return;
    }
    if (!mounted || seq != _seq) return;

    final stream = detail.preferredStream ?? detail.bestStream;
    if (stream == null) {
      setState(() => _pageLoading = false);
      return;
    }

    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await ctrl.initialize();
    } catch (_) {
      await ctrl.dispose();
      if (mounted && seq == _seq) setState(() => _pageLoading = false);
      return;
    }
    if (!mounted || seq != _seq) {
      await ctrl.dispose();
      return;
    }

    ctrl.setVolume(_muted ? 0 : 1);
    _controller = ctrl;
    setState(() {
      _pageLoading = false;
      _titleText = detail.title;
      _totalTime = _fmt(ctrl.value.duration);
    });
    await ctrl.play();
    _startTimer();
    WakelockPlus.enable();
    if (mounted) setState(() {});

    // Smart preload: next item **detail only** (not a second player)
    _prefetchDetail(index + 1);
  }

  void _prefetchDetail(int index) {
    if (index < 0 || index >= widget.items.length) return;
    if (_detailCache.containsKey(index)) return;
    if (_prefetchingIndex == index) return;
    _prefetchingIndex = index;
    final url = widget.items[index].url;
    _fetchDetail(url).then((d) {
      if (!mounted) return;
      _detailCache[index] = d;
      // Drop far cache to save memory
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
    _progressTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!ctrl.value.isInitialized) return;
      final pos = ctrl.value.position;
      final dur = ctrl.value.duration;
      if (dur.inMilliseconds <= 0) return;
      _slider.value =
          (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
      _curTime.value = _fmt(pos);
      final t = _fmt(dur);
      if (t != _totalTime && mounted) setState(() => _totalTime = t);
    });
  }

  void _onPageChanged(int page) {
    if (page == _index) return;
    _playIndex(page);
  }

  void _seek(double v) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    c.seekTo(Duration(milliseconds: (c.value.duration.inMilliseconds * v).round()));
    _slider.value = v;
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
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
              itemCount: widget.items.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, i) {
                if (i == _index &&
                    _controller != null &&
                    _controller!.value.isInitialized) {
                  return Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  );
                }
                final thumb = widget.items[i].thumb;
                return Container(
                  color: const Color(0xFF1A1A1A),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb != null && thumb.isNotEmpty)
                        Image.network(
                          thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      if (i == _index && _pageLoading)
                        const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF6B35),
                          ),
                        ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 80,
                        child: Text(
                          widget.items[i].title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (_controller != null || _pageLoading) ...[
              Positioned(
                left: 12,
                right: 56,
                bottom: 56,
                child: SafeArea(
                  child: Text(
                    _titleText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 56,
                child: SafeArea(
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        _muted = !_muted;
                        _controller?.setVolume(_muted ? 0 : 1);
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          _muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        ValueListenableBuilder<String>(
                          valueListenable: _curTime,
                          builder: (_, t, __) => Text(
                            t,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ValueListenableBuilder<double>(
                            valueListenable: _slider,
                            builder: (_, v, __) => Slider(
                              value: v.clamp(0.0, 1.0),
                              activeColor: const Color(0xFFFF6B35),
                              inactiveColor: Colors.white24,
                              onChanged: _seek,
                            ),
                          ),
                        ),
                        Text(
                          _totalTime,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
