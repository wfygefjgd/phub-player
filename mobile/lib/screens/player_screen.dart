import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/video_item.dart';
import '../services/download_service.dart';
import '../services/phub_api.dart';
import '../utils/http_headers.dart';

class PlayerScreen extends StatefulWidget {
  final VideoItem item;

  const PlayerScreen({super.key, required this.item});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _httpHeaders = AppHttpHeaders.browser;

  VideoPlayerController? _controller;
  VideoDetail? _detail;
  StreamQuality? _current;
  bool _loading = true;
  String? _error;
  bool _landscape = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<PhubApi>();
      final detail = await api.getVideoDetail(widget.item.url);
      if (!mounted) return;

      if (detail.countryBlocked) {
        setState(() {
          _error = '该视频在当前地区不可用';
          _detail = detail;
          _loading = false;
        });
        return;
      }
      if (detail.unavailable || detail.streams.isEmpty) {
        setState(() {
          _error = '无法获取播放地址';
          _detail = detail;
          _loading = false;
        });
        return;
      }

      final stream = detail.preferredStream!;
      _detail = detail;
      _current = stream;
      await _play(stream.url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _play(String url) async {
    await _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: _httpHeaders,
    );
    await _controller!.initialize();
    _controller!.addListener(_onPlayerEvent);
    if (!mounted) return;
    setState(() => _loading = false);
    _controller!.play();
    WakelockPlus.enable();
  }

  void _onPlayerEvent() {
    if (!mounted || _controller == null) return;
    if (_controller!.value.hasError) {
      setState(() {
        _error = _controller!.value.errorDescription ?? '播放错误';
      });
    }
  }

  Future<void> _switchQuality(StreamQuality q) async {
    if (_current?.url == q.url) return;
    final pos = _controller?.value.position;
    final wasPlaying = _controller?.value.isPlaying ?? false;
    setState(() => _current = q);
    await _play(q.url);
    if (pos != null && pos.inSeconds > 0) {
      _controller!.seekTo(pos);
    }
    if (wasPlaying) _controller!.play();
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() {});
  }

  void _toggleLandscape() {
    setState(() => _landscape = !_landscape);
    if (_landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _toggleMute() {
    if (_controller == null) return;
    _muted = !_muted;
    _controller!.setVolume(_muted ? 0 : 1);
    setState(() {});
  }

  Future<void> _downloadCurrent() async {
    if (_current == null || _detail == null) return;
    final url = _current!.url;
    final title = _detail!.title;
    final q = _current!.label;
    final downloader = context.read<DownloadService>();
    if (downloader.browserMode) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    final task = DownloadTask(
      url: url,
      quality: q,
      headers: _httpHeaders,
      title: title,
    );
    await downloader.enqueue(task);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('下载已开始: $title ($q)'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A2A2A),
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller?.removeListener(_onPlayerEvent);
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.title ?? widget.item.title;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _landscape
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                if (_detail != null && _detail!.streams.length > 1)
                  PopupMenuButton<StreamQuality>(
                    tooltip: '清晰度',
                    icon: const Icon(Icons.high_quality),
                    onSelected: _switchQuality,
                    itemBuilder: (_) => [
                      for (final s in _detail!.streams)
                        PopupMenuItem(
                          value: s,
                          child: Text(
                            s.label + (_current?.url == s.url ? '  ✓' : ''),
                          ),
                        ),
                    ],
                  ),
                IconButton(
                  tooltip: '全屏',
                  onPressed: _toggleLandscape,
                  icon: const Icon(Icons.fullscreen),
                ),
              ],
            ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: _landscape
                ? MediaQuery.sizeOf(context).aspectRatio
                : 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_controller != null && _controller!.value.isInitialized)
                  GestureDetector(
                    onTap: _togglePlay,
                    child: VideoPlayer(_controller!),
                  )
                else
                  Container(color: Colors.black),
                if (_loading)
                  const CircularProgressIndicator(color: Color(0xFFFF6B35)),
                if (!_loading && _controller != null &&
                    _controller!.value.hasError)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[300], size: 48),
                      const SizedBox(height: 8),
                      Text(
                        _error ?? '播放出错',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B35)),
                        onPressed: _load,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                if (!_loading && _controller == null && _error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B35)),
                          onPressed: _load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                if (_landscape && _controller != null &&
                    _controller!.value.isInitialized)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      color: Colors.white,
                      onPressed: _toggleLandscape,
                      icon: const Icon(Icons.fullscreen_exit),
                    ),
                  ),
                if (!_loading && _controller != null &&
                    _controller!.value.isInitialized &&
                    !_controller!.value.hasError &&
                    _landscape)
                  Positioned(
                    bottom: 24,
                    right: 8,
                    child: _miniControls(),
                  ),
              ],
            ),
          ),
          if (!_landscape && _controller != null &&
              _controller!.value.isInitialized)
            _buildControls(),
          if (!_landscape) ...[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '时长: ${_detail?.durationLabel ?? widget.item.duration}'
                    '${_current != null ? '  ·  ${_current!.label}' : ''}',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_detail != null && _detail!.streams.isNotEmpty) ...[
                    const Text('清晰度',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in _detail!.streams)
                          ChoiceChip(
                            label: Text(s.label),
                            selected: _current?.url == s.url,
                            selectedColor: const Color(0xFFFF6B35),
                            labelStyle: TextStyle(
                              color: _current?.url == s.url
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                            backgroundColor: const Color(0xFF2A2A2A),
                            onSelected: (_) => _switchQuality(s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('下载视频'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                      ),
                      onPressed: _downloadCurrent,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SelectableText(
                    widget.item.url,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControls() {
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _controller!.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
                onPressed: _togglePlay,
              ),
              Text(
                '${_fmt(pos)} / ${_fmt(dur)}',
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _muted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white70,
                  size: 20,
                ),
                onPressed: _toggleMute,
              ),
            ],
          ),
          VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: const Color(0xFFFF6B35),
                bufferedColor: const Color(0xFF555555),
                backgroundColor: const Color(0xFF333333),
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniControls() {
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _controller!.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
            onPressed: _togglePlay,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '${_fmt(pos)} / ${_fmt(dur)}',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}
