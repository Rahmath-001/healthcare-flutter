package com.healthcare.healthcare_mobile

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Adds screenshot/screen-recording protection for screens showing protected
 * health information.
 *
 * FLAG_SECURE is applied per screen rather than app-wide: leaving it on
 * permanently also blanks the app in the recent-apps switcher, which users
 * report as a bug.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "in.midoctor.app/screen_protection"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    // runOnUiThread: window flags must be set on the UI thread,
                    // and the channel handler is not guaranteed to be on it.
                    runOnUiThread {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE,
                        )
                    }
                    result.success(null)
                }

                "disable" -> {
                    runOnUiThread {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
