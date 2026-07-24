import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'http_headers.dart';

/// Shared Dio factory. Proxy only when [applyProxyConfig] has a real endpoint.
/// Never hardcodes host/port.
class AppHttpClient {
  AppHttpClient._();

  static bool proxyEnabled = false;
  static String proxyHost = '';
  static int proxyPort = 0;
  static String proxyType = 'http';

  static void applyProxyConfig({
    required bool enabled,
    required String host,
    required int port,
    required String type,
  }) {
    proxyHost = host.trim();
    proxyPort = (port > 0 && port < 65536) ? port : 0;
    proxyType = type == 'socks5' ? 'socks5' : 'http';
    // Require a real endpoint — never proxy to empty/0.
    proxyEnabled = enabled && proxyHost.isNotEmpty && proxyPort > 0;
  }

  static String _findProxy(Uri uri) {
    if (!proxyEnabled || proxyHost.isEmpty || proxyPort <= 0) {
      return 'DIRECT';
    }
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
