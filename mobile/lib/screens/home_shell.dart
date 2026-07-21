import 'dart:ui';

import 'package:flutter/material.dart';

import 'download_screen.dart';
import 'recommend_screen.dart';
import 'search_screen.dart';
import 'video_feed_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _feedKey = GlobalKey<VideoFeedScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _feedKey.currentState?.startPlaying();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Content draws under transparent tab bar (immersive feed)
      extendBody: true,
      body: IndexedStack(index: _index, children: [
        VideoFeedScreen(key: _feedKey),
        const RecommendScreen(),
        const SearchScreen(),
        const DownloadScreen(),
      ]),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              final prev = _index;
              setState(() => _index = i);
              if (i == 0) {
                _feedKey.currentState?.startPlaying();
              } else if (prev == 0) {
                _feedKey.currentState?.pausePlayback();
              }
            },
            backgroundColor: Colors.black.withValues(alpha: 0.28),
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            indicatorColor: const Color(0x33FF6B35),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.smart_display_outlined),
                selectedIcon:
                    Icon(Icons.smart_display, color: Color(0xFFFF6B35)),
                label: '视频流',
              ),
              NavigationDestination(
                icon: Icon(Icons.local_fire_department_outlined),
                selectedIcon: Icon(Icons.local_fire_department,
                    color: Color(0xFFFF6B35)),
                label: '推荐',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                selectedIcon: Icon(Icons.search, color: Color(0xFFFF6B35)),
                label: '搜索',
              ),
              NavigationDestination(
                icon: Icon(Icons.download_outlined),
                selectedIcon: Icon(Icons.download, color: Color(0xFFFF6B35)),
                label: '下载',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
