import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings.dart';
import '../services/player_chrome.dart';
import 'search_screen.dart';
import 'video_feed_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Consumer<AppSettings>(
              builder: (_, settings, __) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const ListTile(
                      title: Text('设置',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      dense: true,
                    ),
                    SwitchListTile(
                      title: const Text('跳过片头约 10 秒',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                        '跳过片头广告；短视频自动关闭',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      activeThumbColor: const Color(0xFFFF6B35),
                      value: settings.skipIntro,
                      onChanged: settings.setSkipIntro,
                    ),
                    ListTile(
                      title: const Text('默认画质',
                          style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        settings.qualityLabel,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                      trailing: DropdownButton<int>(
                        value: settings.qualityCap,
                        dropdownColor: const Color(0xFF2A2A2A),
                        underline: const SizedBox.shrink(),
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('自动')),
                          DropdownMenuItem(value: 360, child: Text('360p')),
                          DropdownMenuItem(value: 480, child: Text('480p')),
                          DropdownMenuItem(value: 720, child: Text('720p')),
                          DropdownMenuItem(value: 1080, child: Text('1080p')),
                        ],
                        onChanged: (v) {
                          if (v != null) settings.setQualityCap(v);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final immersive = context.watch<PlayerChrome>().immersive;

    return Scaffold(
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBody(),
          if (!immersive)
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
                      onPressed: _openSettings,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: immersive
          ? null
          : ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) {
                    if (i == _index) return;
                    setState(() => _index = i);
                  },
                  backgroundColor: Colors.black.withValues(alpha: 0.28),
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  indicatorColor: const Color(0x33FF6B35),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.local_fire_department_outlined),
                      selectedIcon: Icon(Icons.local_fire_department,
                          color: Color(0xFFFF6B35)),
                      label: '热',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.public_outlined),
                      selectedIcon:
                          Icon(Icons.public, color: Color(0xFFFF6B35)),
                      label: '亚',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.play_circle_outline),
                      selectedIcon: Icon(Icons.play_circle,
                          color: Color(0xFFFF6B35)),
                      label: 'X',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.subtitles_outlined),
                      selectedIcon:
                          Icon(Icons.subtitles, color: Color(0xFFFF6B35)),
                      label: '中',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search),
                      selectedIcon:
                          Icon(Icons.search, color: Color(0xFFFF6B35)),
                      label: '搜',
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    switch (_index) {
      case 0:
        return const VideoFeedScreen(
          key: ValueKey('feed_hot'),
          kind: VideoFeedKind.hot,
          autoStart: true,
        );
      case 1:
        return const VideoFeedScreen(
          key: ValueKey('feed_asian'),
          kind: VideoFeedKind.asian,
          autoStart: true,
        );
      case 2:
        return const VideoFeedScreen(
          key: ValueKey('feed_x'),
          kind: VideoFeedKind.x,
          autoStart: true,
        );
      case 3:
        return const VideoFeedScreen(
          key: ValueKey('feed_zhong'),
          kind: VideoFeedKind.zhong,
          autoStart: true,
        );
      default:
        return const SearchScreen(key: ValueKey('search'));
    }
  }
}
