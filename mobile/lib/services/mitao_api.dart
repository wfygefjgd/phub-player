import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../models/video_item.dart';
import 'phub_api.dart';

/// mitaohk.com — 中文字幕分类 (MacCMS type id=2).
class MitaoApi {
  static const base = 'https://mitaohk.com';
  /// 中文字幕
  static const zhongTypeId = 2;

  MitaoApi({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
                  'Referer': '$base/',
                },
                followRedirects: true,
                validateStatus: (s) => s != null && s < 500,
              ),
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
    final playRe = RegExp(
      r'/index\.php/vod/play/id/(\d+)/sid/(\d+)/nid/(\d+)\.html',
    );
    // Split by play links
    final chunks = html.split(RegExp(r'(?=/index\.php/vod/play/id/\d+)'));
    for (var i = 1; i < chunks.length; i++) {
      final chunk = chunks[i];
      final pm = playRe.firstMatch(chunk);
      if (pm == null) continue;
      final id = pm.group(1)!;
      if (!seen.add(id)) continue;

      final path =
          '/index.php/vod/play/id/$id/sid/${pm.group(2)}/nid/${pm.group(3)}.html';

      var title = '';
      final t1 = RegExp(r'title="([^"]{2,120})"').firstMatch(chunk);
      if (t1 != null) {
        title = t1.group(1)!;
      } else {
        final t2 = RegExp(r'>([^<]{4,80})</a>').firstMatch(chunk);
        title = t2?.group(1)?.trim() ?? '视频 $id';
      }
      title = title
          .replaceAll('&amp;', '&')
          .replaceAll('&#039;', "'")
          .replaceAll('&quot;', '"')
          .trim();
      if (title.length < 2) title = '视频 $id';

      String? thumb;
      final im = RegExp(
        r'data-original="([^"]+)"|data-src="([^"]+)"|src="((?:https?:)?//[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"',
        caseSensitive: false,
      ).firstMatch(chunk);
      if (im != null) {
        thumb = im.group(1) ?? im.group(2) ?? im.group(3);
        if (thumb != null) thumb = _abs(thumb);
      }

      out.add(VideoItem(
        url: _abs(path),
        title: title,
        duration: '-',
        thumb: thumb,
      ));
    }
    return out;
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
