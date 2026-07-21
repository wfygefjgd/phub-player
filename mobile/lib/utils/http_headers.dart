/// Shared browser-like headers for CDN / site requests.
class AppHttpHeaders {
  static const Map<String, String> browser = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://www.pornhub.com/',
    'Origin': 'https://www.pornhub.com',
  };
}
