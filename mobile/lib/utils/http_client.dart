import 'package:dio/dio.dart';

import 'http_headers.dart';

/// Shared Dio factory — one place for UA / timeouts / status.
class AppHttpClient {
  AppHttpClient._();

  static Dio create({
    Map<String, dynamic>? headers,
    Duration connectTimeout = const Duration(seconds: 20),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) {
    return Dio(
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
  }
}
