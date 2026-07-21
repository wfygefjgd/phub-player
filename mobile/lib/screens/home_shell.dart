import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
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

  bool get _iosSlim => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _feedKey.currentState?.startPlaying();
    });
  }

  List<Widget> get _pages {
    if (_iosSlim) {
      return [
        VideoFeedScreen(key: _feedKey),
        const SearchScreen(),
      ];
    }
    return [
      VideoFeedScreen(key: _feedKey),
      const RecommendScreen(),
      const SearchScreen(),
      const DownloadScreen(),
    ];
  }

  List<NavigationDestination> get _destinations {
    if (_iosSlim) {
      return const [
        NavigationDestination(
          icon: Icon(Icons.smart_display_outlined),
          selectedIcon: Icon(Icons.smart_display, color: Color(0xFFFF6B35)),
          label: '视频流',
        ),
        NavigationDestination(
          icon: Icon(Icons.search),
          selectedIcon: Icon(Icons.search, color: Color(0xFFFF6B35)),
          label: '搜索',
        ),
      ];
    }
    return const [
      NavigationDestination(
        icon: Icon(Icons.smart_display_outlined),
        selectedIcon: Icon(Icons.smart_display, color: Color(0xFFFF6B35)),
        label: '视频流',
      ),
      NavigationDestination(
        icon: Icon(Icons.local_fire_department_outlined),
        selectedIcon:
            Icon(Icons.local_fire_department, color: Color(0xFFFF6B35)),
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final dests = _destinations;
    final idx = _index.clamp(0, pages.length - 1);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: idx, children: pages),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: NavigationBar(
            selectedIndex: idx,
            onDestinationSelected: (i) {
              final prev = _index;
              setState(() => _index = i);
              // Feed is always tab 0
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
            destinations: dests,
          ),
        ),
      ),
    );
  }
}
