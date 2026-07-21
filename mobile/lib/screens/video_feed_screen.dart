import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/video_item.dart';
import '../services/phub_api.dart';
import '../services/translator.dart';
import '../utils/http_headers.dart';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

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
  static const _httpHeaders = AppHttpHeaders.browser;

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
      if (!_pages.containsKey(_currentIndex) ||
          _pages[_currentIndex]?.ready != true) {
        _loadPage(_currentIndex);
        _preloadAhead(_currentIndex);
      } else {
        final cur = _pages[_currentIndex];
        cur?.controller?.play();
        WakelockPlus.enable();
      }
      return;
    }
    // List still loading / empty: _loadMore will start playback when ready
  }

  void pausePlayback() {
    _feedVisible = false;
    _pages[_currentIndex]?.controller?.pause();
    WakelockPlus.disable();
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
      final api = context.read<PhubApi>();
      // Cold start: small list but enough URLs so homepage parse failure still works
      var list = await api.fetchRecommend(
        exclude: _seen,
        limit: isCold ? 16 : 40,
        maxUrls: isCold ? 4 : 8,
      );
      // Fallback if first batch empty (homepage structure / geo / cookie)
      if (list.isEmpty && isCold) {
        list = await api.fetchRecommend(
          exclude: _seen,
          limit: 24,
          maxUrls: 10,
        );
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
          _error = '视频流暂无内容，请检查网络或稍后重试';
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
    // Already loading or ready
    final existing = _pages[index];
    if (existing != null) {
      if (existing.ready && existing.controller != null) {
        // Already buffered – just play
        if (index == _currentIndex && _feedVisible) {
          existing.controller!.play();
          _startProgressTimerForPage(index);
          _setCurrentInfo(index);
          final d = existing.detail;
          if (d != null) _translateTitleOnly(d.title);
        }
        return;
      }
      // Still loading – wait for it in the build method
      return;
    }

    // Not started yet – create and fetch
    final page = _PageState()..loading = true;
    _pages[index] = page;

    final api = context.read<PhubApi>();
    VideoDetail detail;
    try {
      detail = await api.getVideoDetail(item.url);
    } catch (_) {
      page.loading = false;
      if (mounted) setState(() {});
      return;
    }
    if (seq != _loadSeq && index != _currentIndex) {
      page.loading = false;
      return;
    }
    page.detail = detail;
    if (!mounted) return;

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
    if (index == _currentIndex && _feedVisible) {
      ctrl.play();
      _startProgressTimerForPage(index);
    } else {
      ctrl.pause(); // buffered but not playing yet
    }
    page.ready = true;
    page.loading = false;

    if (!mounted) return;
    if (index == _currentIndex) {
      _setCurrentInfo(index);
      _translateTitleOnly(detail.title);
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
    });
  }

  void _setCurrentInfo(int index) {
    final page = _pages[index];
    if (page == null || page.detail == null) return;
    final d = page.detail!;
    _totalTime = _fmtDuration(
        Duration(seconds: d.durationSec > 0 ? d.durationSec : 0));
    _sliderValue.value = 0;
    _currentTime.value = '0:00';
    setState(() {
      _titleText = d.title;
    });
  }

  void _preloadAhead(int fromIndex) {
    // Only next page for smoothness + lower memory
    final next = fromIndex + 1;
    if (next >= _items.length) return;
    if (_pages.containsKey(next)) return;
    _startPreload(next);
  }

  void _startPreload(int index) {
    if (index >= _items.length || !mounted) return;
    if (_pages.containsKey(index)) return;
    final page = _PageState()..loading = true;
    _pages[index] = page;
    final api = context.read<PhubApi>();
    final url = _items[index].url;
    api.getVideoDetail(url).then((detail) {
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
      _setCurrentInfo(page);
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