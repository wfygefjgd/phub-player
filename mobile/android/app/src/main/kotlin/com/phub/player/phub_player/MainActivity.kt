package com.phub.player.phub_player

import android.net.ConnectivityManager
import android.net.ProxyInfo
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.URI

/**
 * Exposes system HTTP proxy to Dart so Dio can follow the same path as many
 * other apps when the user uses system proxy (not only TUN).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "phub_player/system_proxy"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSystemProxy" -> result.success(readSystemProxy())
                    else -> result.notImplemented()
                }
            }
    }

    private fun readSystemProxy(): Map<String, Any?> {
        // 1) Default / system properties (often set by proxy apps or ADB)
        val hostProp = System.getProperty("http.proxyHost")
            ?: System.getProperty("https.proxyHost")
        val portProp = System.getProperty("http.proxyPort")
            ?: System.getProperty("https.proxyPort")
        if (!hostProp.isNullOrBlank() && !portProp.isNullOrBlank()) {
            val port = portProp.toIntOrNull()
            if (port != null && port in 1..65535) {
                return mapOf(
                    "host" to hostProp,
                    "port" to port,
                    "type" to "http",
                    "source" to "system_property",
                )
            }
        }

        // 2) ConnectivityManager default proxy (Android API)
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            val proxy: ProxyInfo? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm.defaultProxy
            } else {
                @Suppress("DEPRECATION")
                android.net.Proxy.getDefaultProxyInfo(this)
            }
            if (proxy != null) {
                val h = proxy.host
                val p = proxy.port
                if (!h.isNullOrBlank() && p in 1..65535) {
                    return mapOf(
                        "host" to h,
                        "port" to p,
                        "type" to "http",
                        "source" to "connectivity",
                    )
                }
            }
        } catch (_: Exception) {
        }

        // 3) ProxySelector (PAC / JVM defaults)
        try {
            val list = java.net.ProxySelector.getDefault()
                ?.select(URI("https://www.google.com"))
            if (list != null) {
                for (px in list) {
                    if (px.type() == java.net.Proxy.Type.HTTP ||
                        px.type() == java.net.Proxy.Type.SOCKS
                    ) {
                        val addr = px.address() as? java.net.InetSocketAddress ?: continue
                        val h = addr.hostString ?: continue
                        val p = addr.port
                        if (p in 1..65535) {
                            val t =
                                if (px.type() == java.net.Proxy.Type.SOCKS) "socks5" else "http"
                            return mapOf(
                                "host" to h,
                                "port" to p,
                                "type" to t,
                                "source" to "proxy_selector",
                            )
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }

        return mapOf(
            "host" to null,
            "port" to null,
            "type" to null,
            "source" to "none",
        )
    }
}
