import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'http_headers.dart';

/// Shared Dio factory — UA / timeouts / optional local HTTP·SOCKS proxy.
///
/// Default is **DIRECT** (system route / TUN). When [proxyEnabled] is true,
/// list/detail/translate requests use the user-configured proxy so non-TUN
/// setups (system proxy only for browsers) still work.
class AppHttpClient {
  AppHttpClient._();

  static bool proxyEnabled = false;
  static String proxyHost = '10.0.2.2';
  static int proxyPort = 7890;
  /// `http` or `socks5`
  static String proxyType = 'http';

  /// Call after [AppSettings] load / whenever proxy prefs change.
  static void applyProxyConfig({
    required bool enabled,
    required String host,
    required int port,
    required String type,
  }) {
    proxyEnabled = enabled;
    proxyHost = host.trim().isEmpty ? '10.0.2.2' : host.trim();
    proxyPort = port > 0 && port < 65536 ? port : 7890;
    proxyType = type == 'socks5' ? 'socks5' : 'http';
  }

  static String _findProxy(Uri uri) {
    if (!proxyEnabled) return 'DIRECT';
    final h = proxyHost;
    final p = proxyPort;
    if (proxyType == 'socks5') {
      return 'SOCKS5 $h:$p; SOCKS $h:$p; DIRECT';
    }
    return 'PROXY $h:$p; DIRECT';
  }

  static Dio create({
    Map<String, dynamic>? headers,
    Duration connectTimeout = const Duration(seconds: 12),
    Duration receiveTimeout = const Duration(seconds: 18),
  }) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: {
          ...AppHttpHeaders.browser,
          if (headers != null) ...headers,
        },
        followRedirects: true,
        validateStatus: (s) => s != null && s < 500,
        responseType: ResponseType.plain,
      ),
    );

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.connectionTimeout = connectTimeout;
        client.findProxy = _findProxy;
        return client;
      },
    );

    return dio;
  }
}
