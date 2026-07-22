import '../models/video_item.dart';

/// In-memory list cache per feed tab (player still disposed on leave).
class FeedListCache {
  FeedListCache._();
  static final Map<String, FeedListSnapshot> _map = {};

  static FeedListSnapshot? take(String kind) => _map[kind];

  static void put(String kind, FeedListSnapshot snap) {
    if (snap.items.isEmpty) return;
    _map[kind] = snap;
  }

  static void clear(String kind) => _map.remove(kind);
}

class FeedListSnapshot {
  FeedListSnapshot({
    required this.items,
    required this.seen,
    required this.index,
  });

  final List<VideoItem> items;
  final Set<String> seen;
  final int index;
}
