import 'dart:math';

import 'package:dio/dio.dart';

import '../models/video_item.dart';
import '../utils/http_client.dart';
import '../utils/http_headers.dart';
import 'phub_api.dart';

/// XVideos list + detail (for feed kind "X").
class XvideosApi {
  XvideosApi({Dio? dio})
      : _dio = dio ??
            AppHttpClient.create(
              headers: {
                ...AppHttpHeaders.browser,
                'Referer': 'https://www.xvideos.com/',
                'Origin': 'https://www.xvideos.com',
                'Cookie': 'age_confirmed=1',
                'Accept-Language': 'en-US,en;q=0.9',
              },
            );

  final Dio _dio;

  Future<String> _getHtml(String url) async {
    final res = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ),
    );
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

  /// Keyword search. XVideos uses p=0 for first page.
  Future<List<VideoItem>> search(String query, {int page = 1}) async {
    final raw = query.trim();
    if (raw.isEmpty) return [];
    final q = Uri.encodeQueryComponent(raw);
    final p = (page - 1).clamp(0, 999);
    // Multiple URL shapes — site HTML changes often
    final urls = <String>[
      if (p == 0) ...[
        'https://www.xvideos.com/?k=$q',
        'https://www.xvideos.com/?k=$q&sort=relevance',
        'https://www.xvideos.com/?k=$q&sort=relevance&datef=alltime',
        'https://www.xvideos.com/search/$q',
      ] else ...[
        'https://www.xvideos.com/?k=$q&p=$p',
        'https://www.xvideos.com/?k=$q&p=$p&sort=relevance',
        'https://www.xvideos.com/?k=$q&p=$p&sort=relevance&datef=alltime',
        'https://www.xvideos.com/search/$q/$p',
      ],
    ];
    Object? lastErr;
    for (final url in urls) {
      try {
        final html = await _getHtml(url);
        final list = _parseList(html, <String>{});
        if (list.isNotEmpty) return list;
      } catch (e) {
        lastErr = e;
        continue;
      }
    }
    if (lastErr != null) throw lastErr;
    return [];
  }

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
      final p = rng.nextInt(20);
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
    // Card blocks often use id="video_XXXX" (numeric or mixed)
    final blocks = html.split(RegExp(r'(?=<div[^>]+id="video_[^"]+")'));
    Iterable<String> iterable;
    if (blocks.length > 1) {
      iterable = blocks.skip(1);
    } else {
      // Fallback: split on video hrefs (new layout / search pages)
      iterable = html.split(RegExp(r'(?=href="(?:https?://(?:www\.)?xvideos\.com)?/video\.[a-zA-Z0-9]+/)'));
      if (iterable.length <= 1) {
        iterable = html.split(RegExp(r'(?=href="/video\.[a-zA-Z0-9]+/)'));
      }
    }

    for (final chunk in iterable) {
      final hm = RegExp(
        r'href="(?:https?://(?:www\.)?xvideos\.com)?(/video\.[a-zA-Z0-9]+/[^"#?]+)"',
      ).firstMatch(chunk);
      if (hm == null) continue;
      final path = hm.group(1)!;
      final idM = RegExp(r'/video\.([a-zA-Z0-9]+)').firstMatch(path);
      final id = idM?.group(1) ?? path;
      if (!seen.add(id)) continue;

      String? title;
      // Prefer title on the video link
      final tLink = RegExp(
        r'href="(?:https?://(?:www\.)?xvideos\.com)?/video\.[a-zA-Z0-9]+/[^"]+"[^>]*title="([^"]+)"',
      ).firstMatch(chunk);
      final tTitleFirst = RegExp(
        r'title="([^"]+)"[^>]*href="(?:https?://(?:www\.)?xvideos\.com)?/video\.[a-zA-Z0-9]+/',
      ).firstMatch(chunk);
      if (tLink != null) {
        title = tLink.group(1);
      } else if (tTitleFirst != null) {
        title = tTitleFirst.group(1);
      } else {
        for (final m in RegExp(r'title="([^"]{5,200})"').allMatches(chunk)) {
          final c = m.group(1)!;
          final low = c.toLowerCase();
          if (low.contains('toggle') ||
              low.contains('logo') ||
              low.contains('menu') ||
              low.contains('search') ||
              low.contains('settings') ||
              low.contains('xvideos')) {
            continue;
          }
          title = c;
          break;
        }
      }
      // <p class="title"> / .thumb-under title text
      if (title == null || title.length < 3) {
        final pTitle = RegExp(
          r'class="[^"]*title[^"]*"[^>]*>\s*<a[^>]*>([^<]{3,200})</a>',
          caseSensitive: false,
        ).firstMatch(chunk);
        if (pTitle != null) title = pTitle.group(1);
      }
      // slug fallback from path
      if (title == null || title.length < 3) {
        final slug = path.split('/').last.replaceAll('_', ' ').trim();
        if (slug.length >= 3) title = slug;
      }
      if (title == null || title.length < 3) continue;
      title = title
          .replaceAll('&#039;', "'")
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      String? thumb;
      final tm = RegExp(
        r'data-src="((?:https?:)?//[^"]+)"|data-srcse="((?:https?:)?//[^"]+)"|data-idthumb="((?:https?:)?//[^"]+)"|data-thumb="((?:https?:)?//[^"]+)"|src="((?:https?:)?//[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"',
        caseSensitive: false,
      ).firstMatch(chunk);
      if (tm != null) {
        thumb = tm.group(1) ??
            tm.group(2) ??
            tm.group(3) ??
            tm.group(4) ??
            tm.group(5);
      }
      if (thumb != null && thumb.startsWith('//')) {
        thumb = 'https:$thumb';
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
