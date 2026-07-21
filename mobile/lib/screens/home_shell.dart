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
  final _hotKey = GlobalKey<VideoFeedScreenState>();
  final _asianKey = GlobalKey<VideoFeedScreenState>();

  bool get _iosSlim => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activateFeed(0);
    });
  }

  List<Widget> get _pages {
    if (_iosSlim) {
      // 热闹 | 亚洲 | 搜索
      return [
        VideoFeedScreen(key: _hotKey, kind: VideoFeedKind.hot),
        VideoFeedScreen(key: _asianKey, kind: VideoFeedKind.asian),
        const SearchScreen(),
      ];
    }
    // 热闹 | 亚洲 | 推荐 | 搜索 | 下载
    return [
      VideoFeedScreen(key: _hotKey, kind: VideoFeedKind.hot),
      VideoFeedScreen(key: _asianKey, kind: VideoFeedKind.asian),
      const RecommendScreen(),
      const SearchScreen(),
      const DownloadScreen(),
    ];
  }

  List<NavigationDestination> get _destinations {
    if (_iosSlim) {
      return const [
        NavigationDestination(
          icon: Icon(Icons.local_fire_department_outlined),
          selectedIcon:
              Icon(Icons.local_fire_department, color: Color(0xFFFF6B35)),
          label: '热闹',
        ),
        NavigationDestination(
          icon: Icon(Icons.public_outlined),
          selectedIcon: Icon(Icons.public, color: Color(0xFFFF6B35)),
          label: '亚洲',
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
        icon: Icon(Icons.local_fire_department_outlined),
        selectedIcon:
            Icon(Icons.local_fire_department, color: Color(0xFFFF6B35)),
        label: '热闹',
      ),
      NavigationDestination(
        icon: Icon(Icons.public_outlined),
        selectedIcon: Icon(Icons.public, color: Color(0xFFFF6B35)),
        label: '亚洲',
      ),
      NavigationDestination(
        icon: Icon(Icons.whatshot_outlined),
        selectedIcon: Icon(Icons.whatshot, color: Color(0xFFFF6B35)),
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

  /// Only one vertical feed may play/preload at a time.
  void _activateFeed(int tabIndex) {
    final hot = _hotKey.currentState;
    final asian = _asianKey.currentState;
    if (tabIndex == 0) {
      asian?.pausePlayback(releasePlayers: true);
      hot?.startPlaying();
    } else if (tabIndex == 1) {
      hot?.pausePlayback(releasePlayers: true);
      asian?.startPlaying();
    } else {
      hot?.pausePlayback(releasePlayers: true);
      asian?.pausePlayback(releasePlayers: true);
    }
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
              setState(() => _index = i);
              _activateFeed(i);
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
