import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_item.dart';
import '../services/mitao_api.dart';
import '../services/phub_api.dart';
import '../services/translator.dart';
import '../services/xvideos_api.dart';
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
  late final TabController _tab;

  String _lastQuery = '';
  String? _enQuery; // cached English form for PH/X when input is Chinese

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
    _controller.dispose();
    super.dispose();
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
    _lastQuery = q;
    _enQuery = null;

    setState(() {
      for (final s in _Src.values) {
        _results[s] = [];
        _error[s] = null;
        _loading[s] = true;
        _page[s] = 1;
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
    _enQuery = en;

    // Parallel: do not await sequentially
    // ignore: unawaited_futures
    _searchOne(_Src.ph, en, 1, replace: true);
    // ignore: unawaited_futures
    _searchOne(_Src.x, en, 1, replace: true);
    // 中: keep Chinese keyword for local CMS
    // ignore: unawaited_futures
    _searchOne(_Src.zhong, q, 1, replace: true);
  }

  Future<void> _searchOne(
    _Src src,
    String query,
    int page, {
    required bool replace,
  }) async {
    if (!mounted) return;
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
      if (!mounted) return;
      final merged = replace ? list : [...?_results[src], ...list];
      setState(() {
        _results[src] = merged;
        _page[src] = page;
        _loading[src] = false;
      });
      // Translate titles for PH/X only (中 usually already Chinese)
      if (src != _Src.zhong && list.isNotEmpty) {
        final start = replace ? 0 : merged.length - list.length;
        _translateRange(src, merged, start);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading[src] = false;
        _error[src] = e.toString().replaceFirst('PhubException: ', '');
      });
    }
  }

  Future<void> _loadMore(_Src src) async {
    if (_loading[src] == true || _lastQuery.isEmpty) return;
    final next = (_page[src] ?? 1) + 1;
    final q = src == _Src.zhong ? _lastQuery : (_enQuery ?? _lastQuery);
    await _searchOne(src, q, next, replace: false);
  }

  Future<void> _translateRange(_Src src, List<VideoItem> all, int start) async {
    try {
      final slice = all.sublist(start);
      final zh = await context
          .read<Translator>()
          .batchEnToZh(slice.map((e) => e.title).toList());
      if (!mounted) return;
      setState(() {
        final list = _results[src]!;
        for (var i = 0; i < zh.length; i++) {
          final idx = start + i;
          if (idx < list.length) {
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
        title: const Text('搜索'),
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
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runAll(),
                    decoration: InputDecoration(
                      hintText: '关键词（三源并行）',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onPressed: () => _runAll(),
                  child: const Text('搜索'),
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
                    _searchOne(src, q, 1, replace: true);
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
    return ListView.builder(
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
                  : TextButton(
                      onPressed: () => _loadMore(src),
                      child: const Text(
                        '加载更多',
                        style: TextStyle(color: Color(0xFFFF6B35)),
                      ),
                    ),
            ),
          );
        }
        return VideoCard(
          item: items[i],
          onTap: () => _openFeed(src, i),
        );
      },
    );
  }
}
