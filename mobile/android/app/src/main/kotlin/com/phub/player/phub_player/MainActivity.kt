package com.phub.player.phub_player

import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

/**
 * Android 15 (API 35) crash fix:
 * - Never touch [window] before [super.onCreate] (window not ready → NPE/crash).
 * - Do not force portrait in manifest; allow system/emulator landscape.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // super first — window exists only after this
        super.onCreate(savedInstanceState)
        try {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                @Suppress("DEPRECATION")
                window.isNavigationBarContrastEnforced = false
            }
            if (Build.VERSION.SDK_INT >= 35) {
                // Soften status/nav bars on API 35 edge-to-edge
                window.statusBarColor = android.graphics.Color.TRANSPARENT
                window.navigationBarColor = android.graphics.Color.TRANSPARENT
            }
        } catch (_: Throwable) {
            // Never crash the activity over chrome setup
        }
    }
}
