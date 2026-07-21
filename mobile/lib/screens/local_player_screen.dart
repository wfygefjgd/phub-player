import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LocalPlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const LocalPlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<LocalPlayerScreen> createState() => _LocalPlayerScreenState();
}

class _LocalPlayerScreenState extends State<LocalPlayerScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _muted = false;
  double _sliderValue = 0;
  String _currentTime = '0:00';
  String _totalTime = '0:00';
  Timer? _hideTimer;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final file = File(widget.filePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在')),
        );
        Navigator.pop(context);
      }
      return;
    }
    final ctrl = VideoPlayerController.file(file);
    await ctrl.initialize();
    if (!mounted) return;
    setState(() {
      _controller = ctrl;
      _ready = true;
      _totalTime = _formatDuration(ctrl.value.duration);
    });
    ctrl.addListener(_onPlayerUpdate);
    ctrl.play();
    _isPlaying = true;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_controller == null || !_controller!.value.isInitialized) return;
      setState(() {
        _sliderValue = _controller!.value.position.inMilliseconds /
            _controller!.value.duration.inMilliseconds;
        _currentTime = _formatDuration(_controller!.value.position);
      });
    });
    _startHideTimer();
  }

  void _onPlayerUpdate() {
    if (!mounted) return;
    if (_controller?.value.isPlaying == true) {
      setState(() => _isPlaying = true);
      WakelockPlus.enable();
    } else {
      setState(() => _isPlaying = false);
      WakelockPlus.disable();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
      _startHideTimer();
    }
  }

  void _toggleMute() {
    if (_controller == null) return;
    _muted = !_muted;
    _controller!.setVolume(_muted ? 0 : 1);
    setState(() {});
  }

  void _seek(double v) {
    if (_controller == null) return;
    final pos = (_controller!.value.duration.inMilliseconds * v).round();
    _controller!.seekTo(Duration(milliseconds: pos));
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showControls
          ? AppBar(
              title: Text(widget.title, style: const TextStyle(fontSize: 14)),
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() {
          _showControls = !_showControls;
          if (_showControls) _startHideTimer();
        }),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
            if (_showControls) ...[
              // Top-gradient + back button
              Container(
                height: 100,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
              Positioned(
                left: 4,
                top: 4,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              // Bottom gradient for controls readability
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 100,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: const Color(0xFFFF6B35),
                        inactiveTrackColor: Colors.white24,
                        thumbColor: const Color(0xFFFF6B35),
                      ),
                      child: Slider(
                        value: _sliderValue.clamp(0.0, 1.0),
                        onChanged: _seek,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Text(_currentTime, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: _togglePlay,
                          ),
                          IconButton(
                            icon: Icon(
                              _muted ? Icons.volume_off : Icons.volume_up,
                              color: Colors.white70,
                              size: 20,
                            ),
                            onPressed: _toggleMute,
                          ),
                          Text(_totalTime, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
