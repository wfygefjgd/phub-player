package com.phub.player.phub_player

import android.net.ConnectivityManager
import android.net.ProxyInfo
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.URI

/**
 * System proxy detection + best-effort JVM http(s) proxy props for media stacks.
 * Never invents host/port.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "phub_player/system_proxy"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSystemProxy" -> result.success(readSystemProxy())
                    "applyJvmHttpProxy" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        if (enabled) {
                            val host = call.argument<String>("host")?.trim().orEmpty()
                            val port = call.argument<Int>("port") ?: 0
                            if (host.isNotEmpty() && port in 1..65535) {
                                System.setProperty("http.proxyHost", host)
                                System.setProperty("http.proxyPort", port.toString())
                                System.setProperty("https.proxyHost", host)
                                System.setProperty("https.proxyPort", port.toString())
                                // Clear non-proxy hosts that might block
                                System.clearProperty("http.nonProxyHosts")
                                System.clearProperty("https.nonProxyHosts")
                            }
                        } else {
                            System.clearProperty("http.proxyHost")
                            System.clearProperty("http.proxyPort")
                            System.clearProperty("https.proxyHost")
                            System.clearProperty("https.proxyPort")
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun emptyProxy(): Map<String, Any?> = mapOf(
        "host" to null,
        "port" to null,
        "type" to null,
        "source" to "none",
    )

    private fun readSystemProxy(): Map<String, Any?> {
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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                val proxy: ProxyInfo? = cm.defaultProxy
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
        }

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

        return emptyProxy()
    }
}
