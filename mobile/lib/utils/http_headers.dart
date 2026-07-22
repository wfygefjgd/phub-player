/// Shared browser-like headers for CDN / site requests.
class AppHttpHeaders {
  static const Map<String, String> browser = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://www.pornhub.com/',
    'Origin': 'https://www.pornhub.com',
  };

  /// Thumb / stream headers by media URL host.
  static Map<String, String> forMediaUrl(String? url) {
    final u = (url ?? '').toLowerCase();
    if (u.contains('xvideos') || u.contains('xvideos-cdn') || u.contains('xnxx')) {
      return {
        ...browser,
        'Referer': 'https://www.xvideos.com/',
        'Origin': 'https://www.xvideos.com',
      };
    }
    if (u.contains('mitao') || u.contains('mitaohk')) {
      return {
        ...browser,
        'Referer': 'https://mitaohk.com/',
        'Origin': 'https://mitaohk.com',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };
    }
    return browser;
  }
}
