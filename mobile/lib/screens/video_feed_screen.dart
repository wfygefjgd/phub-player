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
  /// 热闹 — hot / trending mix
  hot,

  /// 亚洲 — category c=1
  asian,

  /// X — XVideos random mix
  x,

  /// 中 — mitaohk 中文字幕 type/2
  zhong,
}

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({
    super.key,
    this.kind = VideoFeedKind.hot,
  });

  final VideoFeedKind kind;

  @override
  VideoFeedScreenState createState() => VideoFeedScreenState();
}

class _PageState {
  VideoDetail? detail;
  VideoPlayerController? controller;
  bool loading = false;
  bool ready = false;
}

class VideoFeedScreenState extends State<VideoFeedScreen>
    with WidgetsBindingObserver {
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

  final List<VideoItem> _items = [];
  final Set<String> _seen = {};
  final PageController _pageCtrl = PageController();
  final Map<int, _PageState> _pages = {};
  int _currentIndex = 0;
  int _loadSeq = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _muted = false;
  bool _autoPlay = false;
  bool _feedVisible = true;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageCtrl.dispose();
    _progressTimer?.cancel();
    _sliderValue.dispose();
    _currentTime.dispose();
    for (final p in _pages.values) {
      p.controller?.dispose();
    }
    _pages.clear();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      pausePlayback();
    } else if (state == AppLifecycleState.resumed &&
        _feedVisible &&
        _autoPlay) {
      _pages[_currentIndex]?.controller?.play();
      WakelockPlus.enable();
    }
  }

  void startPlaying() {
    _feedVisible = true;
    _autoPlay = true;
    // Always try to kick first page when list is ready
    if (!_loading && _items.isNotEmpty) {
      final cur = _pages[_currentIndex];
      if (cur?.ready == true && cur?.controller != null) {
        cur!.controller!.play();
        _startProgressTimerForPage(_currentIndex);
        WakelockPlus.enable();
      } else if (cur?.detail != null && cur?.controller == null) {
        // Had detail after pause/release — re-init controller only
        _loadPage(_currentIndex);
        _preloadAhead(_currentIndex);
      } else {
        _loadPage(_currentIndex);
        _preloadAhead(_currentIndex);
      }
      return;
    }
    if (_items.isEmpty && !_loadingMore) {
      _loadMore();
    }
    // List still loading: _loadMore will start playback when ready
  }

  /// Deactivate this feed (other tab selected). Stops play + drops players
  /// but keeps list / detail so resume is faster.
  void pausePlayback({bool releasePlayers = true}) {
    _feedVisible = false;
    _autoPlay = false;
    _progressTimer?.cancel();
    for (final p in _pages.values) {
      p.controller?.pause();
      if (releasePlayers) {
        p.controller?.dispose();
        p.controller = null;
        p.ready = false;
        p.loading = false;
      }
    }
    WakelockPlus.disable();
  }

  Future<List<VideoItem>> _fetchBatch({
    required bool isCold,
  }) {
    final limit = isCold ? 16 : 40;
    final maxUrls = isCold ? 4 : 8;
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

  String get _feedLabel {
    switch (widget.kind) {
      case VideoFeedKind.asian:
        return '亚洲';
      case VideoFeedKind.x:
        return 'X';
      case VideoFeedKind.zhong:
        return '中';
      case VideoFeedKind.hot:
        return '热闹';
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

  // ---------- data loading ----------

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    final isCold = _items.isEmpty;
    try {
      var list = await _fetchBatch(isCold: isCold);
      // Fallback if first batch empty (structure / geo / cookie)
      if (list.isEmpty && isCold) {
        list = await _fetchBatch(isCold: false);
      }
      for (final item in list) {
        if (_seen.add(item.viewkey)) {
          _items.add(item);
        }
      }
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        if (_loading) _loading = false;
        if (_items.isEmpty) {
          _error = '$_feedLabel暂无内容，请检查网络或稍后重试';
        }
      });
      // Start playback whenever feed is active and we have items
      if (_autoPlay && _items.isNotEmpty) {
        final needStart = !_pages.containsKey(_currentIndex) ||
            _pages[_currentIndex]?.ready != true;
        if (needStart) {
          _loadPage(_currentIndex.clamp(0, _items.length - 1));
        }
        _preloadAhead(_currentIndex);
        // Background fill after cold start
        if (isCold && _items.length < 30) {
          Future.microtask(() => _loadMore());
        }
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

  // ---------- page loading & preloading ----------

  Future<void> _loadPage(int index) async {
    if (index >= _items.length) return;
    final seq = ++_loadSeq;
    final item = _items[index];
    if (!_autoPlay && index == _currentIndex) {
      // Feed not active — do not start network/player work
      return;
    }

    // Already loading or ready
    final existing = _pages[index];
    if (existing != null) {
      if (existing.ready && existing.controller != null) {
        // Already buffered – just play
        if (index == _currentIndex && _feedVisible && _autoPlay) {
          existing.controller!.play();
          _startProgressTimerForPage(index);
          _setCurrentInfo(
            index,
            playerDuration: existing.controller!.value.duration,
          );
          final d = existing.detail;
          if (d != null) _translateTitleOnly(d.title);
        }
        return;
      }
      // Have detail from earlier, rebuild controller only
      if (existing.detail != null && existing.controller == null) {
        existing.loading = true;
        await _initControllerForPage(index, existing, existing.detail!, seq);
        return;
      }
      // Still loading – wait for it in the build method
      if (existing.loading) return;
    }

    // Not started yet – create and fetch
    final page = existing ?? (_PageState()..loading = true);
    page.loading = true;
    _pages[index] = page;

    VideoDetail detail;
    try {
      detail = await _fetchDetail(item.url);
    } catch (_) {
      page.loading = false;
      if (mounted) setState(() {});
      return;
    }
    if (!_autoPlay) {
      page.detail = detail;
      page.loading = false;
      return;
    }
    if (seq != _loadSeq && index != _currentIndex) {
      page.loading = false;
      page.detail = detail;
      return;
    }
    page.detail = detail;
    if (!mounted) return;
    await _initControllerForPage(index, page, detail, seq);
  }

  Future<void> _initControllerForPage(
    int index,
    _PageState page,
    VideoDetail detail,
    int seq,
  ) async {
    if (!_autoPlay) {
      page.loading = false;
      return;
    }

    final stream = detail.preferredStream ?? detail.bestStream;
    if (stream == null) {
      page.loading = false;
      if (mounted) setState(() {});
      return;
    }

    if (index == _currentIndex) {
      _baseSpeed = _estimateBaseSpeed(stream.height);
      _speedLabel = '$_baseSpeed Kbps';
      _lastBufferedMs = 0;
      _lastTickMs = 0;
      _lastPosMs = 0;
    }

    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: _httpHeaders,
    );
    page.controller = ctrl;
    try {
      await ctrl.initialize();
    } catch (_) {
      page.loading = false;
      page.controller = null;
      await ctrl.dispose();
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
    // Stale load (user already swiped away far) — drop controller
    if (index != _currentIndex &&
        (index < _currentIndex - 1 || index > _currentIndex + 2)) {
      page.loading = false;
      page.controller = null;
      await ctrl.dispose();
      _pages.remove(index);
      return;
    }
    ctrl.setVolume(_muted ? 0 : 1);
    page.ready = true;
    page.loading = false;

    if (!mounted) return;
    if (index == _currentIndex) {
      // Prefer player-reported duration (mitao often has no durationSec in API)
      _setCurrentInfo(index, playerDuration: ctrl.value.duration);
      _translateTitleOnly(detail.title);
      if (_feedVisible) {
        ctrl.play();
        _startProgressTimerForPage(index);
      } else {
        ctrl.pause();
      }
    } else {
      ctrl.pause(); // buffered but not playing yet
    }
    setState(() {});
  }

  void _startProgressTimerForPage(int index) {
    final page = _pages[index];
    if (page?.controller == null) return;
    final ctrl = page!.controller!;
    _progressTimer?.cancel();
    _lastBufferedMs = 0;
    _lastTickMs = 0;
    _lastPosMs = 0;
    // 250ms for smoother bar; only rebuild small ValueListenable widgets
    _progressTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!ctrl.value.isInitialized || index != _currentIndex) return;
      final pos = ctrl.value.position;
      final dur = ctrl.value.duration;
      if (dur.inMilliseconds <= 0) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final bufMs = _getBufferedMs(ctrl);
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
          // Full rebuild only when speed text changes (~1s cadence)
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
      // Late duration (common for HLS / mitao): refresh total once known
      if (dur.inMilliseconds > 0) {
        final t = _fmtDuration(dur);
        if (t != _totalTime && mounted) {
          setState(() => _totalTime = t);
        }
      }
    });
  }

  void _setCurrentInfo(int index, {Duration? playerDuration}) {
    final page = _pages[index];
    if (page == null || page.detail == null) return;
    final d = page.detail!;
    var total = playerDuration;
    if (total == null || total.inMilliseconds <= 0) {
      final pd = page.controller?.value.duration;
      if (pd != null && pd.inMilliseconds > 0) total = pd;
    }
    if (total == null || total.inMilliseconds <= 0) {
      total = Duration(seconds: d.durationSec > 0 ? d.durationSec : 0);
    }
    _totalTime = _fmtDuration(total);
    _sliderValue.value = 0;
    _currentTime.value = '0:00';
    setState(() {
      _titleText = d.title;
    });
  }

  void _preloadAhead(int fromIndex) {
    if (!_autoPlay || !_feedVisible) return;
    // Only next page for smoothness + lower memory
    final next = fromIndex + 1;
    if (next >= _items.length) return;
    if (_pages.containsKey(next)) return;
    _startPreload(next);
  }

  void _startPreload(int index) {
    if (!_autoPlay || !_feedVisible) return;
    if (index >= _items.length || !mounted) return;
    if (_pages.containsKey(index)) return;
    final page = _PageState()..loading = true;
    _pages[index] = page;
    final url = _items[index].url;
    _fetchDetail(url).then((detail) {
      if (!mounted || !_pages.containsKey(index)) {
        page.loading = false;
        return;
      }
      // Drop if already out of window
      if (index < _currentIndex - 1 || index > _currentIndex + 1) {
        _pages.remove(index);
        page.loading = false;
        return;
      }
      page.detail = detail;
      final stream = detail.preferredStream ?? detail.bestStream;
      if (stream == null) {
        page.loading = false;
        return;
      }
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(stream.url),
        httpHeaders: _httpHeaders,
      );
      page.controller = ctrl;
      ctrl.initialize().then((_) {
        if (!mounted || !_pages.containsKey(index)) {
          ctrl.dispose();
          return;
        }
        if (index < _currentIndex - 1 || index > _currentIndex + 1) {
          page.controller = null;
          ctrl.dispose();
          _pages.remove(index);
          return;
        }
        ctrl.setVolume(_muted ? 0 : 1);
        ctrl.pause();
        page.ready = true;
        page.loading = false;
        if (mounted) setState(() {});
      }).catchError((_) {
        page.loading = false;
        page.controller = null;
        ctrl.dispose();
      });
    }).catchError((_) {
      page.loading = false;
      _pages.remove(index);
    });
  }

  void _cleanupDistant() {
    final toRemove = <int>[];
    // Keep only previous + current + next
    for (final i in _pages.keys) {
      if (i < _currentIndex - 1 || i > _currentIndex + 1) {
        toRemove.add(i);
      }
    }
    for (final i in toRemove) {
      final p = _pages.remove(i);
      p?.controller?.dispose();
    }
  }

  // ---------- navigation ----------

  void _onPageChanged(int page) {
    // Pause old
    final oldPage = _pages[_currentIndex];
    oldPage?.controller?.pause();

    _currentIndex = page;

    // Play new (or load if not ready)
    final newPage = _pages[page];
    if (newPage != null && newPage.ready && newPage.controller != null) {
      newPage.controller!.play();
      _startProgressTimerForPage(page);
      _setCurrentInfo(
        page,
        playerDuration: newPage.controller!.value.duration,
      );
      final d = newPage.detail;
      if (d != null) _translateTitleOnly(d.title);
      WakelockPlus.enable();
    } else {
      _loadPage(page);
      WakelockPlus.enable();
    }

    // Preload ahead
    _preloadAhead(page);
    _cleanupDistant();

    // More items if near end
    if (page >= _items.length - 2) {
      _loadMore();
    }
  }

  // ---------- helpers ----------

  Future<void> _translateTitleOnly(String title) async {
    if (title.isEmpty) return;
    try {
      final tr = context.read<Translator>();
      final zh = await tr.enToZh(title);
      if (!mounted || zh.isEmpty) return;
      setState(() => _titleText = zh);
    } catch (_) {}
  }

  double _getBufferedMs(VideoPlayerController ctrl) {
    final ranges = ctrl.value.buffered;
    if (ranges.isEmpty) return 0;
    return ranges.last.end.inMilliseconds.toDouble();
  }

  int _estimateBaseSpeed(int height) {
    if (height >= 1080) return 4500;
    if (height >= 720) return 2800;
    if (height >= 480) return 1500;
    if (height >= 360) return 900;
    return 600;
  }

  void _seek(double v) {
    final page = _pages[_currentIndex];
    if (page?.controller == null) return;
    final pos = (page!.controller!.value.duration.inMilliseconds * v).round();
    page.controller!.seekTo(Duration(milliseconds: pos));
    _sliderValue.value = v;
  }

  void _toggleMute() {
    _muted = !_muted;
    for (final p in _pages.values) {
      p.controller?.setVolume(_muted ? 0 : 1);
    }
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

  // ---------- UI ----------

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
                  _error ?? '视频流为空',
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
                    _autoPlay = true;
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
          if (!_autoPlay) return;
          final page = _pages[_currentIndex];
          if (page?.controller != null) {
            if (page!.controller!.value.isPlaying) {
              page.controller!.pause();
            } else {
              page.controller!.play();
            }
          }
        },
        onLongPressStart: (_) {
          if (!_autoPlay) return;
          _pages[_currentIndex]?.controller?.setPlaybackSpeed(3.0);
        },
        onLongPressEnd: (_) {
          if (!_autoPlay) return;
          _pages[_currentIndex]?.controller?.setPlaybackSpeed(1.0);
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              itemCount: _items.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, i) => _buildPage(i),
            ),
            // Info overlays for current page
            if (_autoPlay && _pages.containsKey(_currentIndex)) ...[
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

  Widget _buildPage(int i) {
    final page = _pages[i];
    final thumbUrl = _items[i].thumb;

    // Page ready with controller: show video player
    if (page != null && page.ready && page.controller != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: page.controller!.value.aspectRatio,
          child: VideoPlayer(page.controller!),
        ),
      );
    }

    // Loading or not yet loaded: show thumbnail + spinner
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbUrl != null && thumbUrl.isNotEmpty)
            Image.network(
              thumbUrl,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (page != null && page.loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
            ),
        ],
      ),
    );
  }

  Widget _buildTitleOverlay() {
    final title = _titleText.isNotEmpty
        ? _titleText
        : (_pages[_currentIndex]?.detail?.title ??
            (_currentIndex < _items.length ? _items[_currentIndex].title : ''));
    return Positioned(
      left: 8,
      top: 4,
      right: _speedLabel.isNotEmpty ? 100 : 8,
      child: SafeArea(
        child: Text(
          title,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              shadows: [Shadow(color: Colors.black87, blurRadius: 4)]),
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
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildMuteButton() {
    return Positioned(
      right: 4,
      bottom: 52,
      child: SafeArea(
        child: _smallIconButton(
          _muted ? Icons.volume_off : Icons.volume_up,
          _toggleMute,
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

  Widget _smallIconButton(IconData icon, VoidCallback onTap) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}