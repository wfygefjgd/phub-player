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
  final Map<String, String> _cache = {};

  Future<String> enToZh(String text) async {
    final key = text.trim();
    if (key.isEmpty) return text;
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final encoded = Uri.encodeQueryComponent(
        key.length > 5000 ? key.substring(0, 5000) : key,
      );
      final url =
          'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&q=$encoded';
      final res = await _dio.get(url);
      final data = res.data;
      if (data is! List || data.isEmpty || data[0] is! List) return text;
      final buf = StringBuffer();
      for (final part in data[0] as List) {
        if (part is List && part.isNotEmpty && part[0] != null) {
          buf.write(part[0]);
        }
      }
      final out = buf.toString();
      final result = out.isEmpty ? text : out;
      _cache[key] = result;
      return result;
    } catch (_) {
      return text;
    }
  }

  Future<List<String>> batchEnToZh(List<String> texts) async {
    if (texts.isEmpty) return [];
    // Resolve cache hits first; only request uncached lines.
    final out = List<String>.filled(texts.length, '');
    final needIdx = <int>[];
    final needTexts = <String>[];
    for (var i = 0; i < texts.length; i++) {
      final t = texts[i];
      final hit = _cache[t.trim()];
      if (hit != null) {
        out[i] = hit;
      } else {
        needIdx.add(i);
        needTexts.add(t);
      }
    }
    if (needTexts.isEmpty) return out;

    try {
      final joined = needTexts.join('\n');
      final encoded = Uri.encodeQueryComponent(
        joined.length > 5000 ? joined.substring(0, 5000) : joined,
      );
      final url =
          'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&q=$encoded';
      final res = await _dio.get(url);
      final data = res.data;
      if (data is! List || data.isEmpty || data[0] is! List) {
        for (var k = 0; k < needIdx.length; k++) {
          out[needIdx[k]] = needTexts[k];
        }
        return out;
      }
      final buf = StringBuffer();
      for (final part in data[0] as List) {
        if (part is List && part.isNotEmpty && part[0] != null) {
          buf.write(part[0]);
        }
      }
      final lines = buf.toString().split('\n');
      for (var k = 0; k < needIdx.length; k++) {
        final src = needTexts[k];
        final zh = k < lines.length && lines[k].isNotEmpty ? lines[k] : src;
        out[needIdx[k]] = zh;
        _cache[src.trim()] = zh;
      }
      return out;
    } catch (_) {
      for (var k = 0; k < needIdx.length; k++) {
        out[needIdx[k]] = await enToZh(needTexts[k]);
      }
      return out;
    }
  }
}
