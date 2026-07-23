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
import '../services/app_settings.dart';
import '../services/feed_list_cache.dart';
import '../services/player_chrome.dart';
import '../utils/http_headers.dart';
import '../utils/playback_helpers.dart';
import '../widgets/player_settings_sheet.dart';

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
  late final PageController _pageCtrl;

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
  int _failStreak = 0;
  final Map<int, VideoDetail> _detailCache = {};
  int? _prefetchingIndex;
  bool _seeking = false;
  VideoDetail? _currentDetail;
  /// Height of the stream currently playing (0 if unknown).
  int _currentStreamHeight = 0;
  /// One-shot quality for current item only (stall accept); does not persist.
  int? _sessionQualityCap;
  /// Stall detection for "try lower quality?" prompt (user must confirm).
  int _stallTicks = 0;
  bool _stallPromptOpen = false;
  bool _stallPromptDismissedForItem = false;
  /// Ignore stall until this timestamp (ms since epoch).
  int _stallArmedAfterMs = 0;
  PlayerChrome? _chrome;
  String get _cacheKey => widget.kind.name;

  int get _effectiveQualityCap =>
      _sessionQualityCap ?? context.read<AppSettings>().qualityCap;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome ??= context.read<PlayerChrome>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _muted = context.read<AppSettings>().muted;
    final snap = FeedListCache.take(_cacheKey);
    if (snap != null && snap.items.isNotEmpty) {
      _items.addAll(snap.items);
      _seen.addAll(snap.seen);
      _currentIndex = snap.index.clamp(0, _items.length - 1);
      _loading = false;
    }
    _pageCtrl = PageController(initialPage: _currentIndex);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) startPlaying();
      });
    }
  }

  @override
  void dispose() {
    if (_items.isNotEmpty) {
      FeedListCache.put(
        _cacheKey,
        FeedListSnapshot(
          items: List<VideoItem>.from(_items),
          seen: Set<String>.from(_seen),
          index: _currentIndex,
        ),
      );
    }
    // Do not use context after dispose; cached chrome only
    try {
      _chrome?.ensurePortraitChrome();
    } catch (_) {}
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

  Future<void> _toggleFullscreen() async {
    await context.read<PlayerChrome>().toggleFullscreen();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _controller?.pause();
      WakelockPlus.disable();
      // Background freezes progress — don't treat as stall when returning.
      _stallTicks = 0;
      _stallPromptOpen = false;
      _stallArmedAfterMs =
          DateTime.now().millisecondsSinceEpoch + 5000;
    } else if (state == AppLifecycleState.resumed && _active) {
      _stallTicks = 0;
      _stallArmedAfterMs =
          DateTime.now().millisecondsSinceEpoch + 5000;
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
      final addedStart = _items.length;
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
      // PH / X titles are English — batch translate after list load.
      if (widget.kind != VideoFeedKind.zhong && _items.length > addedStart) {
        // ignore: unawaited_futures
        _translateItemsRange(addedStart);
      }
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
        if (_items.isEmpty) {
          _error = PlaybackHelpers.friendlyError(e);
        } else if (mounted) {
          PlaybackHelpers.toast(
            context,
            '加载更多失败：${PlaybackHelpers.friendlyError(e)}',
          );
        }
      });
    }
  }

  void _scheduleSkipToNext(int fromIndex) {
    _failStreak++;
    if (_failStreak > 8 || !_active) {
      _failStreak = 0;
      return;
    }
    if (mounted) PlaybackHelpers.toast(context, '已跳过无法播放的视频');
    final next = fromIndex + 1;
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || !_active) return;
      if (next < _items.length) {
        if (_pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(next);
        } else {
          _playIndex(next);
        }
      } else {
        _loadMore();
      }
    });
  }

  void _prefetchDetail(int index) {
    if (!_active || index < 0 || index >= _items.length) return;
    if (_detailCache.containsKey(index)) return;
    if (_prefetchingIndex == index) return;
    _prefetchingIndex = index;
    final url = _items[index].url;
    _fetchDetail(url).then((d) {
      if (!mounted || !_active) return;
      _detailCache[index] = d;
      _detailCache.removeWhere((k, _) => (k - _currentIndex).abs() > 2);
    }).catchError((_) {}).whenComplete(() {
      if (_prefetchingIndex == index) _prefetchingIndex = null;
    });
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
    _currentStreamHeight = 0;
    _stallTicks = 0;
    _stallPromptDismissedForItem = false;
    // Arm stall detection after intro window (~4s), avoids open-buffer false alarms.
    _stallArmedAfterMs =
        DateTime.now().millisecondsSinceEpoch + 4000;
    _sliderValue.value = 0;
    _currentTime.value = '0:00';

    VideoDetail detail;
    try {
      if (_detailCache.containsKey(index)) {
        detail = _detailCache[index]!;
      } else {
        detail = await _fetchDetail(item.url);
        _detailCache[index] = detail;
      }
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _pageLoading = false);
      PlaybackHelpers.toast(
        context,
        '详情加载失败：${PlaybackHelpers.friendlyError(e)}',
      );
      _scheduleSkipToNext(index);
      return;
    }
    if (!mounted || seq != _loadSeq || !_active) return;

    if (detail.countryBlocked) {
      setState(() => _pageLoading = false);
      PlaybackHelpers.toast(context, '该视频在当前地区不可用，已跳过');
      _scheduleSkipToNext(index);
      return;
    }
    if (detail.unavailable) {
      setState(() => _pageLoading = false);
      PlaybackHelpers.toast(context, '视频不可用，已跳过');
      _scheduleSkipToNext(index);
      return;
    }

    final cap = _effectiveQualityCap;
    final candidates = PlaybackHelpers.streamCandidates(detail, cap);
    if (candidates.isEmpty) {
      setState(() => _pageLoading = false);
      PlaybackHelpers.toast(context, '无可用播放地址，已跳过');
      _scheduleSkipToNext(index);
      return;
    }

    _currentDetail = detail;

    VideoPlayerController? ctrl;
    StreamQuality? stream;
    var triedFallback = false;
    for (final c in candidates) {
      if (!mounted || seq != _loadSeq || !_active) {
        await ctrl?.dispose();
        return;
      }
      final next = VideoPlayerController.networkUrl(
        Uri.parse(c.url),
        httpHeaders: _httpHeaders,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );
      try {
        await next.initialize();
        if (triedFallback && mounted) {
          PlaybackHelpers.toast(context, '已切换到 ${c.label}');
        }
        ctrl = next;
        stream = c;
        break;
      } catch (_) {
        triedFallback = true;
        try {
          await next.dispose();
        } catch (_) {}
      }
    }
    if (ctrl == null || stream == null) {
      if (mounted && seq == _loadSeq) {
        setState(() => _pageLoading = false);
        PlaybackHelpers.toast(context, '播放器初始化失败，已跳过');
        _scheduleSkipToNext(index);
      }
      return;
    }
    _baseSpeed = _estimateBaseSpeed(stream.height);
    _currentStreamHeight = stream.height;
    if (!mounted || seq != _loadSeq || !_active) {
      await ctrl.dispose();
      return;
    }

    _failStreak = 0;
    _muted = context.read<AppSettings>().muted;
    ctrl.setVolume(_muted ? 0 : 1);
    final skip = context.read<AppSettings>().skipIntro;
    await PlaybackHelpers.skipIntro(ctrl, enabled: skip);
    if (!mounted || seq != _loadSeq || !_active) {
      await ctrl.dispose();
      return;
    }
    // Non-null after the null check above (loop-assigned locals need bang for analyzer).
    final VideoPlayerController player = ctrl!;
    _controller = player;
    setState(() {
      _pageLoading = false;
      _titleText = detail.title;
      _totalTime = PlaybackHelpers.fmtDuration(player.value.duration);
    });
    _translateTitleOnly(detail.title);
    await player.play();
    _startProgressTimer();
    WakelockPlus.enable();
    if (mounted) setState(() {});
    _prefetchDetail(index + 1);
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
    // 200ms feels smoother than 400ms; skip UI while user is dragging.
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!ctrl.value.isInitialized || _seeking) return;
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
        // Stall: playing but position barely advances (buffering / lag).
        // Do NOT auto-switch quality — only prompt; user must confirm.
        final isPlaying = ctrl.value.isPlaying;
        final nearEnd = posMs >= dur.inMilliseconds - 800;
        final armed = now >= _stallArmedAfterMs;
        if (armed &&
            isPlaying &&
            !nearEnd &&
            dMs >= 150 &&
            dPlayed < 40 &&
            posMs > 2000) {
          _stallTicks++;
        } else if (dPlayed >= 80) {
          _stallTicks = 0;
        }
        if (_stallTicks >= 12) {
          _stallTicks = 0;
          // ignore: unawaited_futures
          _maybePromptLowerQuality();
        }
      }
      _lastBufferedMs = bufMs;
      _lastTickMs = now;
      _lastPosMs = posMs;
      _sliderValue.value =
          (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
      _currentTime.value = PlaybackHelpers.fmtDuration(pos);
      if (dur.inMilliseconds > 0) {
        final t = PlaybackHelpers.fmtDuration(dur);
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
    // Already Chinese (e.g. 中 tab) — keep as-is.
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(title)) {
      if (mounted) setState(() => _titleText = title);
      return;
    }
    try {
      final zh = await context.read<Translator>().enToZh(title);
      if (!mounted || zh.isEmpty) return;
      setState(() => _titleText = zh);
      // Also update list item so next swipe shows Chinese immediately.
      final i = _currentIndex;
      if (i >= 0 && i < _items.length && _items[i].title == title) {
        _items[i] = _items[i].copyWith(title: zh);
      }
    } catch (_) {}
  }

  /// Batch-translate newly loaded English titles; prioritize near current index.
  Future<void> _translateItemsRange(int start) async {
    if (start < 0 || start >= _items.length) return;
    if (widget.kind == VideoFeedKind.zhong) return;
    try {
      final slice = _items.sublist(start);
      final urls = slice.map((e) => e.url).toList();
      final titles = slice.map((e) => e.title).toList();
      // Translate current neighborhood first (snappier UI), then the rest.
      final order = List<int>.generate(titles.length, (i) => i);
      order.sort((a, b) {
        final da = ((start + a) - _currentIndex).abs();
        final db = ((start + b) - _currentIndex).abs();
        return da.compareTo(db);
      });
      final orderedTitles = [for (final i in order) titles[i]];
      final zhOrdered =
          await context.read<Translator>().batchEnToZh(orderedTitles);
      if (!mounted) return;
      final zh = List<String>.filled(titles.length, '');
      for (var k = 0; k < order.length; k++) {
        zh[order[k]] = zhOrdered[k];
      }
      setState(() {
        for (var i = 0; i < zh.length; i++) {
          final idx = start + i;
          if (idx >= _items.length) break;
          if (_items[idx].url != urls[i]) continue;
          if (zh[i].isEmpty || zh[i] == titles[i]) continue;
          _items[idx] = _items[idx].copyWith(title: zh[i]);
          if (idx == _currentIndex &&
              (_titleText == titles[i] || _titleText.isEmpty)) {
            _titleText = zh[i];
          }
        }
      });
    } catch (_) {}
  }

  int _estimateBaseSpeed(int height) {
    if (height >= 1080) return 4500;
    if (height >= 720) return 2800;
    if (height >= 480) return 1500;
    if (height >= 360) return 900;
    return 600;
  }

  /// Drag/tap preview only — never touch the player (prevents snap-back).
  void _onSeekPreview(double v) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final durMs = c.value.duration.inMilliseconds;
    if (durMs <= 0) return;
    final pos = (durMs * v).round();
    _sliderValue.value = v.clamp(0.0, 1.0);
    _currentTime.value =
        PlaybackHelpers.fmtDuration(Duration(milliseconds: pos));
  }

  /// Seek after drag/tap ends; keep [_seeking] until player position settles.
  Future<void> _onSeekCommit(double v) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      _seeking = false;
      return;
    }
    // Cool down stall prompt after seek (buffer refill is normal).
    _stallTicks = 0;
    _stallArmedAfterMs =
        DateTime.now().millisecondsSinceEpoch + 3000;
    final durMs = c.value.duration.inMilliseconds;
    if (durMs <= 0) {
      _seeking = false;
      return;
    }
    final target = v.clamp(0.0, 1.0);
    final posMs = (durMs * target).round();
    _seeking = true;
    _sliderValue.value = target;
    _currentTime.value =
        PlaybackHelpers.fmtDuration(Duration(milliseconds: posMs));
    try {
      await c.seekTo(Duration(milliseconds: posMs));
      // Brief hold so progress timer doesn't overwrite with stale position
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || !identical(c, _controller)) return;
      final p = c.value.position;
      final d = c.value.duration;
      if (d.inMilliseconds > 0) {
        _sliderValue.value =
            (p.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
        _currentTime.value = PlaybackHelpers.fmtDuration(p);
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

  /// Detected lag: ask user before lowering quality. Dismiss = keep current.
  /// Accept only applies to **this item** (session cap), not global settings.
  Future<void> _maybePromptLowerQuality() async {
    if (!mounted || _stallPromptOpen || _stallPromptDismissedForItem) return;
    if (!context.read<AppSettings>().promptOnStall) return;
    final detail = _currentDetail;
    if (detail == null || detail.streams.isEmpty) return;
    final curH = _currentStreamHeight;
    if (curH <= 0) return;
    final lower = detail.streams
        .where((s) => s.height > 0 && s.height < curH)
        .toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    if (lower.isEmpty) return;

    final target = lower.first;
    _stallPromptOpen = true;
    try {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('播放较卡', style: TextStyle(color: Colors.white)),
          content: Text(
            '检测到卡顿。是否切换到更低清晰度 ${target.label}？\n'
            '仅影响本条视频。点「继续」将按当前画质继续播（可能仍卡）。',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('切换到 ${target.label}'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (ok == true) {
        _sessionQualityCap = target.height;
        if (mounted) {
          PlaybackHelpers.toast(context, '正在切换到 ${target.label}（仅本条）');
          // ignore: unawaited_futures
          _playIndex(_currentIndex);
        }
      } else {
        // User declined or dismissed — do not auto-switch; don't nag this item.
        _stallPromptDismissedForItem = true;
      }
    } finally {
      _stallPromptOpen = false;
    }
  }

  void _openPlayerSettings() {
    final detail = _currentDetail;
    final heights = <int>[];
    if (detail != null) {
      for (final s in detail.streams) {
        if (s.height > 0) heights.add(s.height);
      }
    }
    showPlayerSettingsSheet(
      context,
      qualityHeights: heights.isEmpty ? null : heights,
      onQualityChanged: () {
        // Manual quality from settings is global preference + re-open current.
        _sessionQualityCap = null;
        if (mounted) _playIndex(_currentIndex);
      },
    );
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
                            gaplessPlayback: true,
                            headers: AppHttpHeaders.forMediaUrl(thumb),
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
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
              // Fullscreen: settings top-left, exit top-right; mute stays bottom-right.
              if (immersive) ...[
                Positioned(
                  top: 8,
                  left: 8,
                  child: SafeArea(
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: '设置 / 画质',
                        icon: const Icon(Icons.tune,
                            color: Colors.white70, size: 20),
                        onPressed: _openPlayerSettings,
                      ),
                    ),
                  ),
                ),
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
                ),
                if (_controller != null || _pageLoading)
                  Positioned(
                    right: 10,
                    bottom: 56,
                    child: SafeArea(
                      child: FeedSideControls(
                        muted: _muted,
                        onMute: _toggleMute,
                      ),
                    ),
                  ),
              ] else if (_controller != null || _pageLoading) ...[
                _buildTopBar(),
                // Fullscreen under title, left
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
                // Settings (quality etc.) top-right on player
                Positioned(
                  top: 0,
                  right: 6,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Material(
                        color: Colors.black45,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: '设置',
                          icon: const Icon(Icons.tune,
                              color: Colors.white70, size: 20),
                          onPressed: _openPlayerSettings,
                        ),
                      ),
                    ),
                  ),
                ),
                // Mute only on right side
                Positioned(
                  right: 10,
                  bottom: 56,
                  child: SafeArea(
                    child: FeedSideControls(
                      muted: _muted,
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
                      slider: _sliderValue,
                      curTime: _currentTime,
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

  /// Title + speed on one row (leave left gap for fullscreen under title).
  Widget _buildTopBar() {
    final title = _titleText.isNotEmpty
        ? _titleText
        : (_currentIndex < _items.length ? _items[_currentIndex].title : '');
    return Positioned(
      left: 10,
      right: 10,
      top: 8,
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                ),
              ),
            ),
            if (_speedLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            ],
          ],
        ),
      ),
    );
  }
}
