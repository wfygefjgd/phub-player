import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/video_item.dart';

/// Pure-client API: scrapes pornhub.com HTML (no backend, no built-in proxy).
/// Network/VPN is handled by the user / system.
class PhubApi {
  PhubApi({Dio? dio})
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
                  'Accept-Language': 'en-US,en;q=0.9',
                  'Referer': 'https://www.pornhub.com/',
                  'Origin': 'https://www.pornhub.com',
                },
                // Follow redirects; site often sets age cookies via redirect.
                followRedirects: true,
                validateStatus: (s) => s != null && s < 500,
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Cookie'] = _cookieHeader();
          handler.next(options);
        },
        onResponse: (response, handler) {
          _storeCookies(response);
          handler.next(response);
        },
      ),
    );
  }

  final Dio _dio;
  final Map<String, String> _cookies = {
    'accessAgeDisclaimerPH': '1',
    'accessAgeDisclaimerUK': '1',
    'accessPH': '1',
    'age_verified': '1',
    'cookieBannerState': '1',
    'platform': 'pc',
  };

  static final _flashvarsRe =
      RegExp(r'var\s+flashvars_\d+\s*=\s*(\{.*?\});', dotAll: true);
  static final _viewkeyRe = RegExp(r'viewkey=([a-f0-9]+)');
  static final _durationRe = RegExp(
    r'class="[^"]*duration[^"]*"[^>]*>\s*(\d+:\d+(?::\d+)?)\s*<',
  );
  static final _durRe = RegExp(
    r'class="[^"]*dur[^"]*"[^>]*>\s*(\d+:\d+(?::\d+)?)\s*<',
  );

  String _cookieHeader() =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  void _storeCookies(Response response) {
    final raw = response.headers.map['set-cookie'];
    if (raw == null) return;
    for (final line in raw) {
      final part = line.split(';').first;
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final k = part.substring(0, i).trim();
      final v = part.substring(i + 1).trim();
      if (k.isNotEmpty) _cookies[k] = v;
    }
  }

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

  /// Home / hot / trending style feeds (mirrors desktop recommend scrape).
  /// [maxUrls] caps how many list pages to hit (smaller = faster first open).
  Future<List<VideoItem>> fetchRecommend({
    int limit = 50,
    Set<String>? exclude,
    int maxUrls = 12,
  }) async {
    final rng = Random();
    // Prefer video list pages first (homepage markup often differs / empty parse)
    final baseOrders = ['ht', 'cm', 'md', 'tr', 'vi', 'mv', 'tf', 'mr'];
    final urls = <String>[
      'https://www.pornhub.com/video?o=ht',
      'https://www.pornhub.com/video?o=mr',
      'https://www.pornhub.com/video',
      'https://www.pornhub.com/recommended',
      'https://www.pornhub.com/',
    ];
    for (final order in baseOrders) {
      final page = 1 + rng.nextInt(30);
      urls.add('https://www.pornhub.com/video?o=$order&page=$page');
    }
    // Keep hot/recent first; shuffle the rest for variety
    final rest = urls.sublist(2)..shuffle(rng);
    final ordered = [urls[0], urls[1], ...rest];

    final seen = <String>{};
    if (exclude != null) seen.addAll(exclude);
    final results = <VideoItem>[];
    var tried = 0;

    for (final u in ordered) {
      if (tried >= maxUrls) break;
      tried++;
      try {
        final html = await _getHtml(u);
        results.addAll(_parseVideoListHtml(html, seen));
      } catch (_) {
        continue;
      }
      if (results.length >= limit) break;
    }

    results.shuffle(rng);
    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  Future<List<VideoItem>> search(String query, {int page = 1}) async {
    final q = Uri.encodeQueryComponent(query.trim());
    if (q.isEmpty) return [];
    final url =
        'https://www.pornhub.com/video/search?search=$q&page=$page';
    final html = await _getHtml(url);
    return _parseVideoListHtml(html, <String>{});
  }

  Future<VideoDetail> getVideoDetail(String url) async {
    final normalized = _normalizeVideoUrl(url);
    final html = await _getHtml(normalized);
    final match = _flashvarsRe.firstMatch(html);
    if (match == null) {
      throw PhubException('无法解析视频数据（可能被地区限制或页面结构变更）');
    }

    Map<String, dynamic> flash;
    try {
      flash = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    } catch (e) {
      throw PhubException('flashvars JSON 解析失败: $e');
    }

    final title = (flash['video_title'] ?? '').toString();
    var desc = flash['video_description']?.toString();
    // Fallback: extract description from HTML meta tags
    if (desc == null || desc.isEmpty) {
      final ogDesc = RegExp(
              r'<meta\s+property="og:description"\s+content="([^"]+)"',
              caseSensitive: false)
          .firstMatch(html);
      desc = ogDesc?.group(1);
    }
    if (desc == null || desc.isEmpty) {
      final metaDesc = RegExp(
              r'<meta\s+name="description"\s+content="([^"]+)"',
              caseSensitive: false)
          .firstMatch(html);
      desc = metaDesc?.group(1);
    }
    // Strip HTML tags
    if (desc != null) {
      desc = desc.replaceAll(RegExp(r'<[^>]+>'), '');
      desc = desc.replaceAll('&amp;', '&').replaceAll('&#039;', "'")
          .replaceAll('&quot;', '"').replaceAll('&nbsp;', ' ');
      // Filter generic site taglines that are not real descriptions
      if (_isGenericDesc(desc)) desc = null;
    }
    final durationSec = int.tryParse('${flash['video_duration']}') ?? 0;
    final thumb = flash['image_url']?.toString();
    final unavailable = '${flash['video_unavailable']}' != 'false';
    final countryBlocked = '${flash['video_unavailable_country']}' == 'true';
    final isVertical = '${flash['isVertical']}' == 'true';

    final streams = <StreamQuality>[];
    final defs = flash['mediaDefinitions'];
    if (defs is List) {
      for (final raw in defs) {
        if (raw is! Map) continue;
        final q = Map<String, dynamic>.from(raw);
        if (q['format'] != 'hls') continue;
        final videoUrl = q['videoUrl']?.toString();
        if (videoUrl == null || videoUrl.isEmpty) continue;

        var width = int.tryParse('${q['width'] ?? 0}') ?? 0;
        var height = int.tryParse('${q['height'] ?? 0}') ?? 0;
        if (height <= 0) {
          height = _parseQuality(q['quality']) ??
              _parseQualityFromUrl(videoUrl) ??
              0;
        }
        if (width <= 0 && height > 0) {
          width = isVertical
              ? (height * 9 / 16).round()
              : (height * 16 / 9).round();
        }
        if (width <= 0 && height <= 0) continue;
        streams.add(StreamQuality(width: width, height: height, url: videoUrl));
      }
    }

    streams.sort((a, b) => b.pixels.compareTo(a.pixels));

    return VideoDetail(
      url: normalized,
      title: title.isEmpty ? normalized : title,
      description: desc,
      durationSec: durationSec,
      thumb: thumb,
      streams: streams,
      unavailable: unavailable,
      countryBlocked: countryBlocked,
    );
  }

  /// Fetch a single video's page just to retrieve its thumbnail URL.
  Future<String?> fetchThumbnail(String viewkey) async {
    try {
      final html = await _getHtml(
          'https://www.pornhub.com/view_video.php?viewkey=$viewkey');
      final m = _flashvarsRe.firstMatch(html);
      if (m != null) {
        final flash = jsonDecode(m.group(1)!) as Map<String, dynamic>;
        final t = flash['image_url']?.toString();
        if (t != null && t.startsWith('http')) return t;
      }
      final og =
          RegExp(r'<meta\s+property="og:image"\s+content="([^"]+)"')
              .firstMatch(html);
      if (og != null) return og.group(1);
      // fallback: first img with http src in the page
      final imgM =
          RegExp(r'<img[^>]+src="(https?://[^"]+\.(?:jpg|jpeg|png|webp))"',
                  caseSensitive: false)
              .firstMatch(html);
      return imgM?.group(1);
    } catch (_) {
      return null;
    }
  }

  List<VideoItem> _parseVideoListHtml(String html, Set<String> seen) {
    // Run both parsers: chunk-based (fast, comprehensive) + DOM (fallback).
    // Merge results so items missing thumb from one pass get it from the other.
    final results = _parseViaViewkeyChunks(html, seen);
    final domItems = _parseViaDom(html, seen);
    for (final item in domItems) {
      if (!seen.contains(item.viewkey)) {
        results.add(item);
      }
    }
    return results;
  }

  /// Splits HTML by every occurrence of "view_video.php?viewkey=" so that
  /// no video entry is missed, regardless of its CSS class.
  List<VideoItem> _parseViaViewkeyChunks(String html, Set<String> seen) {
    final results = <VideoItem>[];
    final chunks =
        html.split(RegExp(r'(?=view_video\.php\?viewkey=[a-f0-9]+)'));
    if (chunks.length < 2) return results;

    for (var i = 1; i < chunks.length; i++) {
      final chunk = chunks[i];
      final vkM = _viewkeyRe.firstMatch(chunk);
      if (vkM == null) continue;
      final vk = vkM.group(1)!;
      if (!seen.add(vk)) continue;

      final title = _extractTitle(chunk);
      if (title == null) continue;

      final dur = _extractDuration(chunk);
      if (dur != '-') {
        final secs = _durationToSeconds(dur);
        if (secs != null && secs < 30) continue;
      }

      final thumb = _extractThumbFromChunk(chunk);

      results.add(VideoItem(
        url: 'https://www.pornhub.com/view_video.php?viewkey=$vk',
        title: title,
        duration: dur,
        thumb: thumb,
      ));
    }
    return results;
  }

  String? _extractTitle(String chunk) {
    final m = RegExp(r'title="([^"]{5,})"').firstMatch(chunk);
    if (m == null) return null;
    return m
        .group(1)!
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"');
  }

  String _extractDuration(String chunk) {
    final m = _durationRe.firstMatch(chunk) ?? _durRe.firstMatch(chunk);
    return m?.group(1)!.trim() ?? '-';
  }

  String? _extractThumbFromChunk(String chunk) {
    final m = RegExp(r'data-src="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-thumb="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-thumb_url="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-mediumthumb="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-image="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-original="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-lazy-src="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-srcset="[^"]*(https?://[^"\s,]+)"').firstMatch(chunk) ??
        RegExp(r'img[^>]+src="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'poster="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-preview_url="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-thumb_url_v3="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r'data-mediabook="(https?://[^"]+)"').firstMatch(chunk) ??
        RegExp(r"""background(?:-image)?:\s*url\(['"]?(https?://[^'" )]+)""")
            .firstMatch(chunk);
    if (m != null) return m.group(1);
    // Ultra fallback: any PH CDN image URL anywhere in the chunk
    final ph =
        RegExp(r"""https?://[a-z0-9]+\.phncdn\.com/[^"'\s<>)]+\.(?:jpg|jpeg|png|webp)""",
                caseSensitive: false)
            .firstMatch(chunk);
    return ph?.group(0);
  }

  List<VideoItem> _parseViaDom(String html, Set<String> seen) {
    final doc = html_parser.parse(html);
    final results = <VideoItem>[];
    final anchors = doc.querySelectorAll('a[href*="view_video.php?viewkey="]');

    for (final a in anchors) {
      final href = a.attributes['href'] ?? '';
      final vkM = _viewkeyRe.firstMatch(href);
      if (vkM == null) continue;
      final vk = vkM.group(1)!;
      if (!seen.add(vk)) continue;

      var title = a.attributes['title'] ??
          a.querySelector('img')?.attributes['alt'] ??
          a.text.trim();
      title = title
          .replaceAll('&#039;', "'")
          .replaceAll('&amp;', '&')
          .trim();
      if (title.length < 3) continue;

      var dur = '-';
      final parent = a.parent;
      final durNode = parent?.querySelector('.duration') ??
          parent?.querySelector('var.duration');
      if (durNode != null) {
        dur = durNode.text.trim();
      }

      final thumb = _extractThumbFromDom(a);

      results.add(VideoItem(
        url: 'https://www.pornhub.com/view_video.php?viewkey=$vk',
        title: title,
        duration: dur,
        thumb: (thumb != null && thumb.startsWith('http')) ? thumb : null,
      ));
    }
    return results;
  }

  String? _extractThumbFromDom(Element a) {
    final img = a.querySelector('img');
    if (img != null) {
      final t = img.attributes['data-src'] ??
          img.attributes['src'] ??
          img.attributes['data-thumb'] ??
          img.attributes['data-thumb_url'] ??
          img.attributes['data-mediumthumb'] ??
          img.attributes['data-image'] ??
          img.attributes['data-preview_url'] ??
          img.attributes['data-thumb_url_v3'] ??
          img.attributes['data-original'] ??
          img.attributes['data-lazy-src'];
      if (t != null && t.startsWith('http')) return t;
    }
    // Walk up to find a container with a thumb attribute or background-image
    var el = a.parent;
    while (el != null) {
      for (final attr in el.attributes.keys.cast<String>()) {
        final val = el.attributes[attr]!;
        if ((attr.startsWith('data-') && val.startsWith('http')) ||
            (attr == 'poster' && val.startsWith('http'))) {
          // Prefer CDN images over generic URLs
          if (val.contains('phncdn.com')) return val;
        }
      }
      final style = el.attributes['style'] ?? '';
      final bg =
          RegExp(r"""background-image:\s*url\(['"]?(https?://[^'" )]+)""")
              .firstMatch(style);
      if (bg != null) {
        final u = bg.group(1)!;
        if (u.contains('phncdn.com')) return u;
      }
      el = el.parent;
    }
    return null;
  }

  String _normalizeVideoUrl(String url) {
    final t = url.trim();
    if (t.startsWith('http')) return t;
    if (t.contains('viewkey=')) {
      return 'https://www.pornhub.com/view_video.php?$t';
    }
    // bare viewkey
    if (RegExp(r'^[a-f0-9]+$').hasMatch(t)) {
      return 'https://www.pornhub.com/view_video.php?viewkey=$t';
    }
    return t;
  }

  int? _durationToSeconds(String dur) {
    try {
      final parts = dur.split(':').map(int.parse).toList();
      if (parts.length == 2) return parts[0] * 60 + parts[1];
      if (parts.length == 3) {
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      }
    } catch (_) {}
    return null;
  }

  int? _parseQuality(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) return int.tryParse(digits);
    }
    return null;
  }

  static bool _isGenericDesc(String? text) {
    if (text == null || text.trim().isEmpty) return true;
    final s = text.toLowerCase();
    if (s.contains('最好的') ||
        s.contains('免费硬色情') ||
        s.contains('免费色情影片') ||
        s.contains('the best free') ||
        s.contains("best free porn") ||
        s.contains('pornhub.com')) {
      return true;
    }
    return false;
  }

  int? _parseQualityFromUrl(String url) {
    for (final part in url.split('/')) {
      if (part.toLowerCase().contains('p_')) {
        final prefix = part.split(RegExp(r'[Pp]_')).first;
        return _parseQuality(prefix);
      }
    }
    return null;
  }
}

class PhubException implements Exception {
  final String message;
  PhubException(this.message);
  @override
  String toString() => message;
}
