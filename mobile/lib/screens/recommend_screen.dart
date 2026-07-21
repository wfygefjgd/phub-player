import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_item.dart';
import '../services/phub_api.dart';
import '../services/translator.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen>
    with AutomaticKeepAliveClientMixin {
  List<VideoItem> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _translate = true;
  final _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<PhubApi>();
      final list = await api.fetchRecommend(limit: 10, maxUrls: 2);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
      if (_translate && list.isNotEmpty) {
        _doTranslate(list, 0);
      }
      _retryMissingThumbs();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final api = context.read<PhubApi>();
      final list = await api.fetchRecommend(limit: 10, maxUrls: 2);
      if (!mounted) return;
      final start = _items.length;
      setState(() {
        _items.addAll(list);
        _loadingMore = false;
      });
      if (_translate && list.isNotEmpty) {
        _doTranslate(list, start);
      }
      _retryMissingThumbs();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _doTranslate(List<VideoItem> slice, int start) async {
    try {
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

  void _retryMissingThumbs() async {
    final api = context.read<PhubApi>();
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].thumb != null) continue;
      final vk = _items[i].viewkey;
      final thumb = await api.fetchThumbnail(vk);
      if (!mounted) return;
      if (thumb != null) {
        setState(() {
          _items[i] = _items[i].copyWith(thumb: thumb);
        });
      }
    }
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
        title: const Text('推荐'),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '翻译标题',
            onPressed: _items.isEmpty
                ? null
                : () {
                    setState(() => _translate = true);
                    _doTranslate(_items, 0);
                  },
            icon: const Icon(Icons.translate),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
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
              const SizedBox(height: 12),
              const Text(
                '请确认手机网络可访问源站（用户自行解决网络）',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35)),
                onPressed: _load,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
if (_items.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department,
                    size: 48, color: Color(0xFFFF6B35)),
                const SizedBox(height: 12),
                const Text('点击上方刷新按钮加载推荐视频',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35)),
                  onPressed: _load,
                  child: const Text('立即刷新'),
                ),
              ],
            ),
          ),
        );
      }
    return RefreshIndicator(
      color: const Color(0xFFFF6B35),
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Color(0xFFFF6B35),
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          }
          return VideoCard(
            item: _items[i],
            onTap: () => _open(_items[i]),
          );
        },
      ),
    );
  }
}
