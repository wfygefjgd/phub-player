import 'dart:math';

import 'package:dio/dio.dart';

import '../models/video_item.dart';
import '../utils/http_headers.dart';
import 'phub_api.dart';

/// XVideos list + detail (for feed kind "X").
class XvideosApi {
  XvideosApi({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
                headers: {
                  ...AppHttpHeaders.browser,
                  'Referer': 'https://www.xvideos.com/',
                  'Origin': 'https://www.xvideos.com',
                  'Cookie': 'age_confirmed=1',
                },
                followRedirects: true,
                validateStatus: (s) => s != null && s < 500,
              ),
            );

  final Dio _dio;

  static final _videoHrefRe =
      RegExp(r'href="(/video\.[a-zA-Z0-9]+/[^"]+)"');
  static final _titleRe = RegExp(r'title="([^"]{5,200})"');
  static final _thumbRe = RegExp(
    r'data-src="(https?://[^"]+)"|data-idthumb="(https?://[^"]+)"|src="(https?://[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"',
    caseSensitive: false,
  );

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

  /// Keyword search (page starts at 0 on xvideos: p=0 is first page).
  Future<List<VideoItem>> search(String query, {int page = 1}) async {
    final q = Uri.encodeQueryComponent(query.trim());
    if (q.isEmpty) return [];
    final p = (page - 1).clamp(0, 999);
    final url = p == 0
        ? 'https://www.xvideos.com/?k=$q'
        : 'https://www.xvideos.com/?k=$q&p=$p';
    final html = await _getHtml(url);
    return _parseList(html, <String>{});
  }

  /// Random mix of home / asian keyword / best pages (like 热闹 regeneration).
  Future<List<VideoItem>> fetchFeed({
    int limit = 40,
    Set<String>? exclude,
    int maxUrls = 8,
  }) async {
    final rng = Random();
    final keywords = [
      'asian',
      'japanese',
      'chinese',
      'korean',
      'thai',
      'milf',
      'teen',
      'amateur',
    ];
    final urls = <String>[
      'https://www.xvideos.com/',
      'https://www.xvideos.com/?k=asian',
      'https://www.xvideos.com/best',
    ];
    for (final k in keywords) {
      final p = rng.nextInt(20); // 0..19
      urls.add(
        p == 0
            ? 'https://www.xvideos.com/?k=$k'
            : 'https://www.xvideos.com/?k=$k&p=$p',
      );
    }
    urls.shuffle(rng);

    final seen = <String>{...?exclude};
    final results = <VideoItem>[];
    var tried = 0;
    for (final u in urls) {
      if (tried >= maxUrls) break;
      tried++;
      try {
        final html = await _getHtml(u);
        results.addAll(_parseList(html, seen));
      } catch (_) {
        continue;
      }
      if (results.length >= limit) break;
    }
    results.shuffle(rng);
    if (results.length > limit) return results.sublist(0, limit);
    return results;
  }

  List<VideoItem> _parseList(String html, Set<String> seen) {
    final out = <VideoItem>[];
    // Split roughly by video cards
    final chunks = html.split(RegExp(r'(?=href="/video\.[a-zA-Z0-9]+/)'));
    for (var i = 1; i < chunks.length; i++) {
      final chunk = chunks[i];
      final hm = _videoHrefRe.firstMatch(chunk);
      if (hm == null) continue;
      final path = hm.group(1)!;
      // id key: video.xxxxx
      final idM = RegExp(r'/video\.([a-zA-Z0-9]+)').firstMatch(path);
      final id = idM?.group(1) ?? path;
      if (!seen.add(id)) continue;

      final titleM = _titleRe.firstMatch(chunk);
      if (titleM == null) continue;
      var title = titleM
          .group(1)!
          .replaceAll('&#039;', "'")
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"');
      if (title.length < 5) continue;
      // skip UI chrome
      if (title.toLowerCase().contains('toggle')) continue;

      String? thumb;
      final tm = _thumbRe.firstMatch(chunk);
      if (tm != null) {
        thumb = tm.group(1) ?? tm.group(2) ?? tm.group(3);
      }

      out.add(VideoItem(
        url: 'https://www.xvideos.com$path',
        title: title,
        duration: '-',
        thumb: thumb,
      ));
    }
    return out;
  }

  Future<VideoDetail> getVideoDetail(String url) async {
    final html = await _getHtml(url);
    final titleM = RegExp(r"setVideoTitle\('([^']*)'\)").firstMatch(html) ??
        RegExp(r'setVideoTitle\("([^"]*)"\)').firstMatch(html);
    var title = titleM?.group(1) ?? '';
    title = title
        .replaceAll(r"\'", "'")
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&');
    if (title.isEmpty) {
      final t2 = RegExp(r'<title>([^<]+)</title>', caseSensitive: false)
          .firstMatch(html);
      title = (t2?.group(1) ?? url).split('-').first.trim();
    }

    final streams = <StreamQuality>[];
    final hls = RegExp(r"setVideoHLS\('([^']+)'\)").firstMatch(html) ??
        RegExp(r'setVideoHLS\("([^"]+)"\)').firstMatch(html);
    if (hls != null) {
      streams.add(StreamQuality(width: 1280, height: 720, url: hls.group(1)!));
    }
    final high = RegExp(r"setVideoUrlHigh\('([^']+)'\)").firstMatch(html) ??
        RegExp(r'setVideoUrlHigh\("([^"]+)"\)').firstMatch(html);
    if (high != null) {
      streams.add(StreamQuality(width: 640, height: 360, url: high.group(1)!));
    }
    final low = RegExp(r"setVideoUrlLow\('([^']+)'\)").firstMatch(html) ??
        RegExp(r'setVideoUrlLow\("([^"]+)"\)').firstMatch(html);
    if (low != null) {
      streams.add(StreamQuality(width: 426, height: 240, url: low.group(1)!));
    }
    if (streams.isEmpty) {
      throw PhubException('无法解析 X 视频地址');
    }
    streams.sort((a, b) => b.pixels.compareTo(a.pixels));

    final thumbM = RegExp(r"setThumbUrl\('([^']+)'\)").firstMatch(html) ??
        RegExp(r'setThumbUrl169\("([^"]+)"\)').firstMatch(html) ??
        RegExp(r"setThumbUrl169\('([^']+)'\)").firstMatch(html);

    return VideoDetail(
      url: url,
      title: title.isEmpty ? url : title,
      durationSec: 0,
      thumb: thumbM?.group(1),
      streams: streams,
    );
  }
}
