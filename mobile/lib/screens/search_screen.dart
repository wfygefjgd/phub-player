import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_item.dart';
import '../services/mitao_api.dart';
import '../services/phub_api.dart';
import '../services/translator.dart';
import '../services/xvideos_api.dart';
import '../utils/playback_helpers.dart';
import '../widgets/video_card.dart';
import 'search_feed_screen.dart';

/// Built-in 3 sources — parallel search, single active results view.
enum _Src { ph, x, zhong }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final TabController _tab;

  String _lastQuery = '';
  String? _enQuery; // cached English form for PH/X when input is Chinese
  /// Bumps on every new search to drop stale async results/translates.
  int _searchGen = 0;

  final Map<_Src, List<VideoItem>> _results = {
    _Src.ph: [],
    _Src.x: [],
    _Src.zhong: [],
  };
  final Map<_Src, bool> _loading = {
    _Src.ph: false,
    _Src.x: false,
    _Src.zhong: false,
  };
  final Map<_Src, String?> _error = {
    _Src.ph: null,
    _Src.x: null,
    _Src.zhong: null,
  };
  final Map<_Src, int> _page = {
    _Src.ph: 1,
    _Src.x: 1,
    _Src.zhong: 1,
  };
  final Map<_Src, bool> _hasMore = {
    _Src.ph: true,
    _Src.x: true,
    _Src.zhong: true,
  };

  static const _labels = {
    _Src.ph: '热',
    _Src.x: 'X',
    _Src.zhong: '中',
  };

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // Only rebuild active list indicator; body uses single child
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _unfocus() {
    _focus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  _Src get _active {
    switch (_tab.index) {
      case 1:
        return _Src.x;
      case 2:
        return _Src.zhong;
      default:
        return _Src.ph;
    }
  }

  SearchSource _toFeedSource(_Src s) {
    switch (s) {
      case _Src.ph:
        return SearchSource.ph;
      case _Src.x:
        return SearchSource.x;
      case _Src.zhong:
        return SearchSource.zhong;
    }
  }

  Future<void> _runAll() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    _unfocus();
    final gen = ++_searchGen;
    _lastQuery = q;
    _enQuery = null;

    setState(() {
      for (final s in _Src.values) {
        _results[s] = [];
        _error[s] = null;
        _loading[s] = true;
        _page[s] = 1;
        _hasMore[s] = true;
      }
    });

    final tr = context.read<Translator>();
    var en = q;
    if (tr.containsChinese(q)) {
      try {
        final t = await tr.zhToEn(q);
        if (t.trim().isNotEmpty) en = t.trim();
      } catch (_) {}
    }
    if (!mounted || gen != _searchGen) return;
    _enQuery = en;

    // Parallel: do not await sequentially
    // ignore: unawaited_futures
    _searchOne(_Src.ph, en, 1, replace: true, gen: gen);
    // ignore: unawaited_futures
    _searchOne(_Src.x, en, 1, replace: true, gen: gen);
    // 中: keep Chinese keyword for local CMS
    // ignore: unawaited_futures
    _searchOne(_Src.zhong, q, 1, replace: true, gen: gen);
  }

  Future<void> _searchOne(
    _Src src,
    String query,
    int page, {
    required bool replace,
    required int gen,
  }) async {
    if (!mounted || gen != _searchGen) return;
    setState(() {
      _loading[src] = true;
      _error[src] = null;
    });
    try {
      List<VideoItem> list;
      switch (src) {
        case _Src.ph:
          list = await context.read<PhubApi>().search(query, page: page);
          break;
        case _Src.x:
          list = await context.read<XvideosApi>().search(query, page: page);
          break;
        case _Src.zhong:
          list = await context.read<MitaoApi>().search(query, page: page);
          break;
      }
      if (!mounted || gen != _searchGen) return;
      final prev = _results[src] ?? [];
      final seen = <String>{for (final e in (replace ? <VideoItem>[] : prev)) e.viewkey};
      final fresh = <VideoItem>[];
      for (final e in list) {
        if (seen.add(e.viewkey)) fresh.add(e);
      }
      final merged = replace ? fresh : [...prev, ...fresh];
      setState(() {
        _results[src] = merged;
        _page[src] = page;
        _loading[src] = false;
        // Empty page or zero new items => stop paging
        _hasMore[src] = list.isNotEmpty && fresh.isNotEmpty;
      });
      // Translate titles for PH/X only (中 usually already Chinese)
      if (src != _Src.zhong && fresh.isNotEmpty) {
        final start = replace ? 0 : merged.length - fresh.length;
        _translateRange(src, start, gen);
      }
    } catch (e) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _loading[src] = false;
        _error[src] = PlaybackHelpers.friendlyError(e);
      });
    }
  }

  Future<void> _loadMore(_Src src) async {
    if (_loading[src] == true || _lastQuery.isEmpty) return;
    if (_hasMore[src] == false) return;
    final next = (_page[src] ?? 1) + 1;
    final q = src == _Src.zhong ? _lastQuery : (_enQuery ?? _lastQuery);
    await _searchOne(src, q, next, replace: false, gen: _searchGen);
  }

  /// Used by vertical search player to append pages without leaving the feed.
  Future<List<VideoItem>> loadMoreForFeed(SearchSource source) async {
    final src = switch (source) {
      SearchSource.ph => _Src.ph,
      SearchSource.x => _Src.x,
      SearchSource.zhong => _Src.zhong,
    };
    if (_hasMore[src] == false || _loading[src] == true || _lastQuery.isEmpty) {
      return const [];
    }
    final before = (_results[src] ?? []).length;
    await _loadMore(src);
    final all = _results[src] ?? [];
    if (all.length <= before) return const [];
    return all.sublist(before);
  }

  Future<void> _translateRange(_Src src, int start, int gen) async {
    try {
      final all = _results[src];
      if (all == null || start >= all.length) return;
      final slice = all.sublist(start);
      final urls = slice.map((e) => e.url).toList();
      final titles = slice.map((e) => e.title).toList();
      final zh = await context.read<Translator>().batchEnToZh(titles);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        final list = _results[src]!;
        for (var i = 0; i < zh.length; i++) {
          final idx = start + i;
          if (idx >= list.length) break;
          // Match by URL so a later load-more shift won't corrupt titles
          if (list[idx].url == urls[i]) {
            list[idx] = list[idx].copyWith(title: zh[i]);
          }
        }
      });
    } catch (_) {}
  }

  void _openFeed(_Src src, int index) {
    final items = _results[src] ?? [];
    if (items.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchFeedScreen(
          items: List<VideoItem>.from(items),
          source: _toFeedSource(src),
          initialIndex: index,
          title: _labels[src]!,
          onLoadMore: () => loadMoreForFeed(_toFeedSource(src)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final src = _active;
    final items = _results[src] ?? [];
    final loading = _loading[src] ?? false;
    final err = _error[src];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('搜'),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: const Color(0xFFFF6B35),
          labelColor: const Color(0xFFFF6B35),
          unselectedLabelColor: Colors.white54,
          tabs: [
            for (final s in _Src.values)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_labels[s]!),
                    if ((_loading[s] ?? false)) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                    ] else if ((_results[s] ?? []).isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${_results[s]!.length}',
                        style: const TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runAll(),
                    // Keep caret/text inside the rounded field
                    clipBehavior: Clip.hardEdge,
                    decoration: InputDecoration(
                      hintText: '关键词（三源并行）',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                          color: Color(0x55FF6B35),
                          width: 1.2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      prefixIcon: const Icon(Icons.search,
                          color: Colors.white38, size: 20),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: _runAll,
                  child: const Text('搜'),
                ),
              ],
            ),
          ),
          // Single active source view only (no TabBarView with 3 lists)
          Expanded(child: _buildSourceBody(src, items, loading, err)),
        ],
      ),
    );
  }

  Widget _buildSourceBody(
    _Src src,
    List<VideoItem> items,
    bool loading,
    String? err,
  ) {
    if (loading && items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
      );
    }
    if (err != null && items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                err,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                ),
                onPressed: () {
                  final q =
                      src == _Src.zhong ? _lastQuery : (_enQuery ?? _lastQuery);
                  if (q.isEmpty) {
                    _runAll();
                  } else {
                    _searchOne(src, q, 1, replace: true, gen: _searchGen);
                  }
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          _lastQuery.isEmpty ? '输入关键词，三源同时搜索' : '该源暂无结果，可切换其它源',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    final hasMore = _hasMore[src] ?? true;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
          if (hasMore && !loading) _loadMore(src);
        }
        return false;
      },
      child: ListView.builder(
        itemCount: items.length + 1,
        itemBuilder: (_, i) {
          if (i == items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF6B35),
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        hasMore ? '上拉加载更多' : '没有更多了',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
              ),
            );
          }
          return VideoCard(
            item: items[i],
            onTap: () => _openFeed(src, i),
          );
        },
      ),
    );
  }
}
