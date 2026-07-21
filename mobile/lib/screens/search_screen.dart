import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_item.dart';
import '../services/phub_api.dart';
import '../services/translator.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  List<VideoItem> _items = [];
  bool _loading = false;
  String? _error;
  int _page = 1;
  String _lastQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search({bool nextPage = false}) async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;

    final page = nextPage ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
      if (!nextPage) _items = [];
    });

    try {
      final api = context.read<PhubApi>();
      final tr = context.read<Translator>();
      // Scheme A: Chinese keywords → English first (avoids 403 on CJK search)
      var searchQ = q;
      if (!nextPage && tr.containsChinese(q)) {
        final en = await tr.zhToEn(q);
        if (en.trim().isNotEmpty) searchQ = en.trim();
      } else if (nextPage && tr.containsChinese(_lastQuery)) {
        // Keep same English query used for first page
        final en = await tr.zhToEn(_lastQuery);
        if (en.trim().isNotEmpty) searchQ = en.trim();
      }
      final list = await api.search(searchQ, page: page);
      if (!mounted) return;

      final merged = nextPage ? [..._items, ...list] : list;
      setState(() {
        _items = merged;
        _page = page;
        _lastQuery = q;
        _loading = false;
      });

      // translate new titles only
      final start = nextPage ? merged.length - list.length : 0;
      if (list.isNotEmpty) {
        _translateRange(merged, start);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _translateRange(List<VideoItem> all, int start) async {
    try {
      final slice = all.sublist(start);
      final tr = context.read<Translator>();
      final zh = await tr.batchEnToZh(slice.map((e) => e.title).toList());
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < zh.length; i++) {
          final idx = start + i;
          if (idx < _items.length) {
            _items[idx] = _items[idx].copyWith(title: zh[i]);
          }
        }
      });
    } catch (_) {}
  }

  void _open(VideoItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('搜索'),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
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
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: '关键词',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  onPressed: _loading ? null : () => _search(),
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
      );
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35)),
                onPressed: () => _search(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('输入关键词开始搜索', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: _items.length + 1,
      itemBuilder: (_, i) {
        if (i == _items.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator(color: Color(0xFFFF6B35))
                  : TextButton(
                      onPressed: _lastQuery.isEmpty
                          ? null
                          : () => _search(nextPage: true),
                      child: const Text('加载更多',
                          style: TextStyle(color: Color(0xFFFF6B35))),
                    ),
            ),
          );
        }
        return VideoCard(item: _items[i], onTap: () => _open(_items[i]));
      },
    );
  }
}
