import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../models/video_item.dart';
import '../utils/http_client.dart';
import '../utils/http_headers.dart';
import 'phub_api.dart';

/// mitaohk.com — 中文字幕分类 (MacCMS type id=2).
class MitaoApi {
  static const base = 'https://mitaohk.com';
  /// 中文字幕
  static const zhongTypeId = 2;

  MitaoApi({Dio? dio})
      : _dio = dio ??
            AppHttpClient.create(
              headers: {
                ...AppHttpHeaders.browser,
                'Referer': '$base/',
                'Origin': base,
                'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
              },
            );

  final Dio _dio;

  Future<String> _getHtml(String url) async {
    final res = await _dio.get<String>(url);
    if (res.statusCode == 403) {
      throw PhubException('访问被拒绝 (403)，请检查网络环境');
    }
    if (res.statusCode == 404) {
      throw PhubException('页面不存在 (404)');
    }
    if (res.data == null || res.data!.isEmpty) {
      throw PhubException('空响应');
    }
    return res.data!;
  }

  String _abs(String path) {
    if (path.startsWith('http')) return path;
    if (path.startsWith('//')) return 'https:$path';
    if (!path.startsWith('/')) path = '/$path';
    return '$base$path';
  }

  /// Site search (keyword as-is; Chinese OK for this site).
  Future<List<VideoItem>> search(String query, {int page = 1}) async {
    final q = Uri.encodeComponent(query.trim());
    if (q.isEmpty) return [];
    // MacCMS search URL
    final url = page <= 1
        ? '$base/index.php/vod/search/wd/$q.html'
        : '$base/index.php/vod/search/wd/$q/page/$page.html';
    try {
      final html = await _getHtml(url);
      return _parseList(html, <String>{});
    } catch (_) {
      // alternate pattern
      final alt = '$base/index.php/vod/search.html?wd=$q&page=$page';
      final html = await _getHtml(alt);
      return _parseList(html, <String>{});
    }
  }

  /// Random pages of 中文字幕 type list.
  Future<List<VideoItem>> fetchZhong({
    int limit = 40,
    Set<String>? exclude,
    int maxPages = 6,
  }) async {
    final rng = Random();
    final pages = <int>{1};
    while (pages.length < maxPages) {
      pages.add(1 + rng.nextInt(30));
    }
    final ordered = pages.toList()..shuffle(rng);

    final seen = <String>{...?exclude};
    final results = <VideoItem>[];

    for (final p in ordered) {
      final url = p <= 1
          ? '$base/index.php/vod/type/id/$zhongTypeId.html'
          : '$base/index.php/vod/type/id/$zhongTypeId/page/$p.html';
      try {
        final html = await _getHtml(url);
        results.addAll(_parseList(html, seen));
      } catch (_) {
        // try alternate page pattern
        if (p > 1) {
          try {
            final alt =
                '$base/index.php/vod/type/id/$zhongTypeId.html?page=$p';
            final html = await _getHtml(alt);
            results.addAll(_parseList(html, seen));
          } catch (_) {}
        }
      }
      if (results.length >= limit) break;
    }

    results.shuffle(rng);
    if (results.length > limit) return results.sublist(0, limit);
    return results;
  }

  List<VideoItem> _parseList(String html, Set<String> seen) {
    final out = <VideoItem>[];
    final detailRe = RegExp(r'/index\.php/vod/detail/id/(\d+)\.html');
    final playRe = RegExp(
      r'/index\.php/vod/play/id/(\d+)/sid/(\d+)/nid/(\d+)\.html',
    );

    final titles = <String, String>{};
    final thumbs = <String, String>{};
    final playPaths = <String, String>{};

    void considerTitle(String id, String raw) {
      final t = _cleanTitle(raw);
      if (!_isGoodTitle(t, id)) return;
      final prev = titles[id];
      // Prefer longer / CJK-rich titles over short noise
      if (prev == null || _titleScore(t) > _titleScore(prev)) {
        titles[id] = t;
      }
    }

    // Module cards: title attr + href (both orders)
    for (final m in RegExp(
      r'title="([^"]{2,200})"[^>]*href="(/index\.php/vod/(?:detail|play)/id/(\d+)[^"]*)"',
      caseSensitive: false,
    ).allMatches(html)) {
      final id = m.group(3)!;
      considerTitle(id, m.group(1)!);
      final href = m.group(2)!;
      if (href.contains('/play/')) {
        playPaths.putIfAbsent(id, () => href);
      }
    }
    for (final m in RegExp(
      r'href="(/index\.php/vod/(?:detail|play)/id/(\d+)[^"]*)"[^>]*title="([^"]{2,200})"',
      caseSensitive: false,
    ).allMatches(html)) {
      final id = m.group(2)!;
      considerTitle(id, m.group(3)!);
      final href = m.group(1)!;
      if (href.contains('/play/')) {
        playPaths.putIfAbsent(id, () => href);
      }
    }

    // data-original / lazy img alt near detail links
    for (final m in RegExp(
      r'alt="([^"]{2,200})"[^>]*(?:data-original|data-src|src)="([^"]+)"[^>]{0,200}href="[^"]*vod/(?:detail|play)/id/(\d+)',
      caseSensitive: false,
    ).allMatches(html)) {
      considerTitle(m.group(3)!, m.group(1)!);
      thumbs.putIfAbsent(m.group(3)!, () => m.group(2)!);
    }

    // Text inside titled anchors: <a href="...detail/id/N">真实标题</a>
    for (final m in RegExp(
      r'href="(/index\.php/vod/(?:detail|play)/id/(\d+)[^"]*)"[^>]*>\s*([^<]{4,200})\s*<',
      caseSensitive: false,
    ).allMatches(html)) {
      final id = m.group(2)!;
      considerTitle(id, m.group(3)!);
      final href = m.group(1)!;
      if (href.contains('/play/')) {
        playPaths.putIfAbsent(id, () => href);
      }
    }

    for (final m in detailRe.allMatches(html)) {
      final id = m.group(1)!;
      final idx = m.start;
      final start = idx > 800 ? idx - 800 : 0;
      final end = (idx + 600).clamp(0, html.length);
      final ctx = html.substring(start, end);
      final t = _pickTitle(ctx, id);
      if (t.isNotEmpty) considerTitle(id, t);
      final th = _pickThumb(ctx);
      if (th != null) thumbs.putIfAbsent(id, () => th);
    }

    for (final m in playRe.allMatches(html)) {
      final id = m.group(1)!;
      final path =
          '/index.php/vod/play/id/$id/sid/${m.group(2)}/nid/${m.group(3)}.html';
      playPaths.putIfAbsent(id, () => path);
      if (!titles.containsKey(id) || (thumbs[id] == null || thumbs[id]!.isEmpty)) {
        final idx = m.start;
        final start = idx > 800 ? idx - 800 : 0;
        final end = (idx + 600).clamp(0, html.length);
        final ctx = html.substring(start, end);
        if (!titles.containsKey(id)) {
          final t = _pickTitle(ctx, id);
          if (t.isNotEmpty) considerTitle(id, t);
        }
        final th = _pickThumb(ctx);
        if (th != null) thumbs.putIfAbsent(id, () => th);
      }
    }

    // MacCMS list often has .module-item-title / .module-item-pic
    for (final m in RegExp(
      r'class="[^"]*module-item-title[^"]*"[^>]*>\s*<a[^>]*href="[^"]*id/(\d+)[^"]*"[^>]*>([^<]{2,200})</a>',
      caseSensitive: false,
    ).allMatches(html)) {
      considerTitle(m.group(1)!, m.group(2)!);
    }
    for (final m in RegExp(
      r'class="[^"]*module-item-title[^"]*"[^>]*>\s*<a[^>]*title="([^"]{2,200})"[^>]*href="[^"]*id/(\d+)',
      caseSensitive: false,
    ).allMatches(html)) {
      considerTitle(m.group(2)!, m.group(1)!);
    }

    final ids = {...titles.keys, ...playPaths.keys, ...thumbs.keys};
    for (final id in ids) {
      if (!seen.add(id)) continue;
      final path = playPaths[id] ??
          '/index.php/vod/play/id/$id/sid/1/nid/1.html';
      var title = titles[id] ?? '';
      if (!_isGoodTitle(title, id)) {
        title = '未命名 $id';
      }

      final th = thumbs[id];
      out.add(VideoItem(
        url: _abs(path.startsWith('/') ? path : '/$path'),
        title: title,
        duration: '-',
        thumb: (th != null && th.isNotEmpty) ? _abs(th) : null,
      ));
    }
    return out;
  }

  String _cleanTitle(String t) => t
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&#039;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _isGoodTitle(String t, String id) {
    if (t.isEmpty || t.length < 2) return false;
    if (t == id || RegExp(r'^\d+$').hasMatch(t)) return false;
    if (t == '中文字幕' || t == '更多' || t == '播放' || t == '详情') return false;
    if (t.contains('点击') || t.contains('广告')) return false;
    if (t.startsWith('视频') && RegExp(r'^视频\s*\d+$').hasMatch(t)) return false;
    return true;
  }

  int _titleScore(String t) {
    var s = t.length;
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(t)) s += 20;
    return s;
  }

  String _pickTitle(String ctx, String id) {
    final cands = <String>[];
    for (final m in RegExp(r'title="([^"]{2,200})"').allMatches(ctx)) {
      cands.add(_cleanTitle(m.group(1)!));
    }
    for (final m in RegExp(r'alt="([^"]{2,200})"').allMatches(ctx)) {
      cands.add(_cleanTitle(m.group(1)!));
    }
    for (final m in RegExp(
      r'<(?:h[234]|span|p|div)[^>]*class="[^"]*(?:title|name|vod)[^"]*"[^>]*>([^<]{2,200})</',
      caseSensitive: false,
    ).allMatches(ctx)) {
      cands.add(_cleanTitle(m.group(1)!));
    }
    // bare CJK text near link
    for (final m in RegExp(r'>([\u4e00-\u9fff][^<]{3,80})<').allMatches(ctx)) {
      cands.add(_cleanTitle(m.group(1)!));
    }
    String? best;
    for (final t in cands) {
      if (!_isGoodTitle(t, id)) continue;
      if (best == null || _titleScore(t) > _titleScore(best)) best = t;
    }
    return best ?? '';
  }

  String? _pickThumb(String ctx) {
    final im = RegExp(
      r'data-original="([^"]+)"|data-src="([^"]+)"|data-bg="([^"]+)"|src="((?:https?:)?//[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"',
      caseSensitive: false,
    ).firstMatch(ctx);
    if (im == null) return null;
    return im.group(1) ?? im.group(2) ?? im.group(3) ?? im.group(4);
  }

  Future<VideoDetail> getVideoDetail(String url) async {
    final html = await _getHtml(url);
    final m = RegExp(
      r'player_aaaa\s*=\s*(\{[\s\S]*?\})\s*</script>',
    ).firstMatch(html);
    if (m == null) {
      throw PhubException('无法解析播放数据');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(m.group(1)!) as Map<String, dynamic>;
    } catch (e) {
      throw PhubException('播放 JSON 解析失败: $e');
    }

    final encrypt = int.tryParse('${data['encrypt']}') ?? 0;
    var playUrl = (data['url'] ?? '').toString().trim();
    if (playUrl.isEmpty) {
      throw PhubException('播放地址为空');
    }
    if (encrypt == 1) {
      // base64
      try {
        playUrl = utf8.decode(base64.decode(playUrl));
      } catch (_) {
        throw PhubException('播放地址解密失败');
      }
    } else if (encrypt == 2) {
      throw PhubException('暂不支持该加密线路');
    }
    if (!playUrl.startsWith('http')) {
      playUrl = _abs(playUrl);
    }

    String title = '';
    var durationSec = 0;
    final vd = data['vod_data'];
    if (vd is Map) {
      title = (vd['vod_name'] ?? '').toString();
      durationSec = int.tryParse('${vd['vod_duration'] ?? 0}') ?? 0;
      // sometimes "01:23:45" or "23:45"
      if (durationSec <= 0) {
        final ds = (vd['vod_duration'] ?? vd['duration'] ?? '').toString();
        durationSec = _parseDurationText(ds);
      }
    }
    if (durationSec <= 0) {
      final dm = RegExp(r'vod_duration["\s:]+["' "'" r']?(\d+)').firstMatch(html);
      if (dm != null) {
        durationSec = int.tryParse(dm.group(1) ?? '') ?? 0;
      }
    }
    if (title.isEmpty) {
      final tm = RegExp(r'<title>([^<]+)</title>', caseSensitive: false)
          .firstMatch(html);
      title = (tm?.group(1) ?? '视频').split('-').first.trim();
    }

    final streams = <StreamQuality>[
      StreamQuality(width: 1280, height: 720, url: playUrl),
    ];

    return VideoDetail(
      url: url,
      title: title.isEmpty ? url : title,
      durationSec: durationSec,
      streams: streams,
    );
  }

  int _parseDurationText(String s) {
    final t = s.trim();
    if (t.isEmpty) return 0;
    final n = int.tryParse(t);
    if (n != null && n > 0) return n;
    final parts = t.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    if (parts.length == 3) {
      return parts[0] * 3600 + parts[1] * 60 + parts[2];
    }
    if (parts.length == 2) {
      return parts[0] * 60 + parts[1];
    }
    return 0;
  }
}
