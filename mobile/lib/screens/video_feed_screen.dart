import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/video_item.dart';
import '../services/mitao_api.dart';
import '../services/phub_api.dart';
import '../services/translator.dart';
import '../services/xvideos_api.dart';
import '../utils/http_headers.dart';

enum VideoFeedKind {
  hot,
  asian,
  x,
  zhong,
}

/// Vertical feed with **exactly one** VideoPlayerController at a time.
/// Designed for Android stability (ExoPlayer + multi-instance freezes).
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({
    super.key,
    this.kind = VideoFeedKind.hot,
    this.autoStart = false,
  });

  final VideoFeedKind kind;
  final bool autoStart;

  @override
  State<VideoFeedScreen> createState() => VideoFeedScreenState();
}

class VideoFeedScreenState extends State<VideoFeedScreen>
    with WidgetsBindingObserver {
  final List<VideoItem> _items = [];
  final Set<String> _seen = {};
  final PageController _pageCtrl = PageController();

  /// Only the currently playing controller (never multiple).
  VideoPlayerController? _controller;
  int _currentIndex = 0;
  int _loadSeq = 0;

  bool _loading = false;
  bool _loadingMore = false;
  bool _pageLoading = false;
  bool _muted = false;
  bool _active = false;
  String? _error;
  String _titleText = '';
  String _speedLabel = '';

  Timer? _progressTimer;
  final ValueNotifier<double> _sliderValue = ValueNotifier(0);
  final ValueNotifier<String> _currentTime = ValueNotifier('0:00');
  String _totalTime = '0:00';
  int _baseSpeed = 1500;
  double _lastBufferedMs = 0;
  int _lastTickMs = 0;
  double _lastPosMs = 0;
  String _lastSpeedLabel = '';

  Map<String, String> get _httpHeaders {
    switch (widget.kind) {
      case VideoFeedKind.x:
        return {
          ...AppHttpHeaders.browser,
          'Referer': 'https://www.xvideos.com/',
          'Origin': 'https://www.xvideos.com',
        };
      case VideoFeedKind.zhong:
        return {
          ...AppHttpHeaders.browser,
          'Referer': 'https://mitaohk.com/',
          'Origin': 'https://mitaohk.com',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        };
      case VideoFeedKind.hot:
      case VideoFeedKind.asian:
        return AppHttpHeaders.browser;
    }
  }

  String get _feedLabel {
    switch (widget.kind) {
      case VideoFeedKind.asian:
        return '亚';
      case VideoFeedKind.x:
        return 'X';
      case VideoFeedKind.zhong:
        return '中';
      case VideoFeedKind.hot:
        return '热';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) startPlaying();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _sliderValue.dispose();
    _currentTime.dispose();
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
    } else if (state == AppLifecycleState.resumed && _active) {
      _controller?.play();
      WakelockPlus.enable();
    }
  }

  void startPlaying() {
    _active = true;
    if (_items.isEmpty) {
      if (!_loadingMore) {
        setState(() => _loading = true);
        _loadMore();
      }
      return;
    }
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.play();
      _startProgressTimer();
      WakelockPlus.enable();
      return;
    }
    _playIndex(_currentIndex);
  }

  void pausePlayback({bool releasePlayers = true}) {
    _active = false;
    _loadSeq++;
    _progressTimer?.cancel();
    _progressTimer = null;
    final c = _controller;
    _controller = null;
    try {
      c?.pause();
    } catch (_) {}
    WakelockPlus.disable();
    if (releasePlayers && c != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          c.dispose();
        } catch (_) {}
      });
    }
  }

  Future<List<VideoItem>> _fetchBatch({required bool isCold}) {
    final limit = isCold ? 12 : 30;
    final maxUrls = isCold ? 3 : 6;
    switch (widget.kind) {
      case VideoFeedKind.asian:
        return context.read<PhubApi>().fetchAsian(
              exclude: _seen,
              limit: limit,
              maxUrls: maxUrls,
            );
      case VideoFeedKind.hot:
        return context.read<PhubApi>().fetchRecommend(
              exclude: _seen,
              limit: limit,
              maxUrls: maxUrls,
            );
      case VideoFeedKind.x:
        return context.read<XvideosApi>().fetchFeed(
              exclude: _seen,
              limit: limit,
              maxUrls: maxUrls,
            );
      case VideoFeedKind.zhong:
        return context.read<MitaoApi>().fetchZhong(
              exclude: _seen,
              limit: limit,
              maxPages: maxUrls,
            );
    }
  }

  Future<VideoDetail> _fetchDetail(String url) {
    if (url.contains('xvideos.com') || widget.kind == VideoFeedKind.x) {
      return context.read<XvideosApi>().getVideoDetail(url);
    }
    if (url.contains('mitaohk.com') || widget.kind == VideoFeedKind.zhong) {
      return context.read<MitaoApi>().getVideoDetail(url);
    }
    return context.read<PhubApi>().getVideoDetail(url);
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    final isCold = _items.isEmpty;
    try {
      var list = await _fetchBatch(isCold: isCold);
      if (list.isEmpty && isCold) {
        list = await _fetchBatch(isCold: false);
      }
      for (final item in list) {
        if (_seen.add(item.viewkey)) _items.add(item);
      }
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loading = false;
        if (_items.isEmpty) {
          _error = '$_feedLabel暂无内容，请检查网络或稍后重试';
        }
      });
      if (_active && _items.isNotEmpty && _controller == null) {
        _playIndex(_currentIndex.clamp(0, _items.length - 1));
      }
      if (isCold && _items.length < 20 && _active) {
        Future<void>.delayed(const Duration(seconds: 1), () {
          if (mounted && _active) _loadMore();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_items.isEmpty) _error = e.toString();
      });
    }
  }

  Future<void> _playIndex(int index) async {
    if (!_active || index < 0 || index >= _items.length) return;
    final seq = ++_loadSeq;
    final item = _items[index];

    // Tear down previous player completely before creating a new one
    await _disposeController();

    if (!mounted || seq != _loadSeq || !_active) return;
    setState(() {
      _pageLoading = true;
      _currentIndex = index;
      _titleText = item.title;
      _totalTime = '0:00';
      _speedLabel = '';
    });
    _sliderValue.value = 0;
    _currentTime.value = '0:00';

    VideoDetail detail;
    try {
      detail = await _fetchDetail(item.url);
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _pageLoading = false);
      return;
    }
    if (!mounted || seq != _loadSeq || !_active) return;

    // Prefer lower quality on Android for stability
    final stream = detail.preferredStream ?? detail.bestStream;
    if (stream == null) {
      setState(() => _pageLoading = false);
      return;
    }

    _baseSpeed = _estimateBaseSpeed(stream.height);

    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _httpHeaders,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await ctrl.initialize();
    } catch (_) {
      await ctrl.dispose();
      if (mounted && seq == _loadSeq) {
        setState(() => _pageLoading = false);
      }
      return;
    }
    if (!mounted || seq != _loadSeq || !_active) {
      await ctrl.dispose();
      return;
    }

    ctrl.setVolume(_muted ? 0 : 1);
    _controller = ctrl;
    setState(() {
      _pageLoading = false;
      _titleText = detail.title;
      _totalTime = _fmtDuration(ctrl.value.duration);
    });
    _translateTitleOnly(detail.title);
    await ctrl.play();
    _startProgressTimer();
    WakelockPlus.enable();
    if (mounted) setState(() {});
  }

  Future<void> _disposeController() async {
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

  void _startProgressTimer() {
    final ctrl = _controller;
    if (ctrl == null) return;
    _progressTimer?.cancel();
    _lastBufferedMs = 0;
    _lastTickMs = 0;
    _lastPosMs = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!ctrl.value.isInitialized) return;
      final pos = ctrl.value.position;
      final dur = ctrl.value.duration;
      if (dur.inMilliseconds <= 0) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final ranges = ctrl.value.buffered;
      final bufMs = ranges.isEmpty
          ? 0.0
          : ranges.last.end.inMilliseconds.toDouble();
      final posMs = pos.inMilliseconds.toDouble();
      if (_lastTickMs > 0) {
        final dMs = now - _lastTickMs;
        final dBuf = bufMs - _lastBufferedMs;
        final dPlayed = posMs - _lastPosMs;
        final downloaded = (dBuf + dPlayed).clamp(0.0, double.infinity);
        if (dMs > 0 && downloaded > 0) {
          final ratio = (downloaded / dMs).clamp(0.0, 3.0);
          final speed = (_baseSpeed * ratio).round().clamp(0, 20000);
          final label = '$speed Kbps';
          if (label != _lastSpeedLabel) {
            _lastSpeedLabel = label;
            if (mounted) setState(() => _speedLabel = label);
          }
        }
      }
      _lastBufferedMs = bufMs;
      _lastTickMs = now;
      _lastPosMs = posMs;
      _sliderValue.value =
          (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
      _currentTime.value = _fmtDuration(pos);
      if (dur.inMilliseconds > 0) {
        final t = _fmtDuration(dur);
        if (t != _totalTime && mounted) {
          setState(() => _totalTime = t);
        }
      }
    });
  }

  void _onPageChanged(int page) {
    if (page == _currentIndex) return;
    // Hard switch: dispose old, play new only
    _playIndex(page);
    if (page >= _items.length - 3) {
      _loadMore();
    }
  }

  Future<void> _translateTitleOnly(String title) async {
    if (title.isEmpty) return;
    try {
      final zh = await context.read<Translator>().enToZh(title);
      if (!mounted || zh.isEmpty) return;
      setState(() => _titleText = zh);
    } catch (_) {}
  }

  int _estimateBaseSpeed(int height) {
    if (height >= 1080) return 4500;
    if (height >= 720) return 2800;
    if (height >= 480) return 1500;
    if (height >= 360) return 900;
    return 600;
  }

  void _seek(double v) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final pos = (c.value.duration.inMilliseconds * v).round();
    c.seekTo(Duration(milliseconds: pos));
    _sliderValue.value = v;
  }

  void _toggleMute() {
    _muted = !_muted;
    _controller?.setVolume(_muted ? 0 : 1);
    setState(() {});
  }

  String _fmtDuration(Duration d) {
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
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
        ),
      );
    }
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? '$_feedLabel暂无内容',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                  ),
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _active = true;
                    _loadMore();
                  },
                  child: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
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
                if (i == _currentIndex &&
                    _controller != null &&
                    _controller!.value.isInitialized) {
                  return Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
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
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      if (i == _currentIndex && _pageLoading)
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
            if (_controller != null || _pageLoading) ...[
              _buildTitleOverlay(),
              _buildSpeedBadge(),
              _buildMuteButton(),
              _buildProgressBar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitleOverlay() {
    return Positioned(
      left: 8,
      top: 4,
      right: _speedLabel.isNotEmpty ? 100 : 8,
      child: SafeArea(
        child: Text(
          _titleText.isNotEmpty
              ? _titleText
              : (_currentIndex < _items.length
                  ? _items[_currentIndex].title
                  : ''),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildSpeedBadge() {
    if (_speedLabel.isEmpty) return const SizedBox.shrink();
    return Positioned(
      right: 8,
      top: 4,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _speedLabel,
            style: const TextStyle(
              color: Color(0xFF00E676),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMuteButton() {
    return Positioned(
      right: 10,
      bottom: 52,
      child: SafeArea(
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggleMute,
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
    );
  }

  Widget _buildProgressBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Container(
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
                valueListenable: _currentTime,
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
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: const Color(0xFFFF6B35),
                    inactiveTrackColor: Colors.white24,
                    thumbColor: const Color(0xFFFF6B35),
                  ),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _sliderValue,
                    builder: (_, v, __) => Slider(
                      value: v.clamp(0.0, 1.0),
                      onChanged: _seek,
                    ),
                  ),
                ),
              ),
              Text(
                _totalTime,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
