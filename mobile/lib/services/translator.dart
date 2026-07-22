import 'package:dio/dio.dart';

/// Free Google Translate endpoint (same idea as desktop).
class Translator {
  Translator({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
              ),
            );

  final Dio _dio;
  /// Direction-aware cache only: "en_zh-CN:text" / "zh-CN_en:text"
  final Map<String, String> _cache = {};

  static final _zhRe = RegExp(r'[\u4e00-\u9fff]');

  bool containsChinese(String text) => _zhRe.hasMatch(text);

  Future<String> enToZh(String text) async =>
      _translate(text, from: 'en', to: 'zh-CN');

  Future<String> zhToEn(String text) async =>
      _translate(text, from: 'zh-CN', to: 'en');

  Future<String> _translate(
    String text, {
    required String from,
    required String to,
  }) async {
    final raw = text.trim();
    if (raw.isEmpty) return text;
    // Skip en→zh when already mostly Chinese (avoids re-translating cache hits)
    if (from == 'en' && to.startsWith('zh') && containsChinese(raw)) {
      return text;
    }
    final key = '${from}_$to:$raw';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final encoded = Uri.encodeQueryComponent(
        raw.length > 4500 ? raw.substring(0, 4500) : raw,
      );
      final url =
          'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$from&tl=$to&dt=t&q=$encoded';
      final res = await _dio.get(url);
      final data = res.data;
      if (data is! List || data.isEmpty || data[0] is! List) return text;
      final buf = StringBuffer();
      for (final part in data[0] as List) {
        if (part is List && part.isNotEmpty && part[0] != null) {
          buf.write(part[0]);
        }
      }
      final out = buf.toString().trim();
      final result = out.isEmpty ? text : out;
      // Reject obvious garbage one-liners that are far shorter ad noise
      if (_looksLikeGarbageTitle(result) && !_looksLikeGarbageTitle(raw)) {
        return text;
      }
      _cache[key] = result;
      return result;
    } catch (_) {
      return text;
    }
  }

  /// Translate each title separately — NEVER join with \\n.
  /// Joined batch was corrupting search titles on 2nd search.
  Future<List<String>> batchEnToZh(List<String> texts) async {
    if (texts.isEmpty) return [];
    final out = List<String>.filled(texts.length, '');
    // small concurrency without flood; preserve index mapping
    const chunk = 5;
    for (var i = 0; i < texts.length; i += chunk) {
      final end = (i + chunk > texts.length) ? texts.length : i + chunk;
      final futures = <Future<String>>[];
      for (var j = i; j < end; j++) {
        futures.add(enToZh(texts[j]));
      }
      final parts = await Future.wait(futures);
      for (var k = 0; k < parts.length; k++) {
        out[i + k] = parts[k];
      }
    }
    return out;
  }

  static bool _looksLikeGarbageTitle(String t) {
    final s = t.toLowerCase();
    if (s.contains('奖得主') || s.contains('award') || s.contains('winner')) {
      if (s.length < 40) return true;
    }
    if (s.contains('点击') && s.contains('下载')) return true;
    if (s.contains('广告')) return true;
    return false;
  }
}
