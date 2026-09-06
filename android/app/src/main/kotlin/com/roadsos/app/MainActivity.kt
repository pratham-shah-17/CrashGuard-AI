package com.roadsos.app

import android.content.Intent
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.codestreak.roadsos/hardware_buttons"
    private var methodChannel: MethodChannel? = null
    private var volumeUpPresses = 0
    private var volumeDownPresses = 0
    private var lastPressTime: Long = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                // Called by EmergencyBackgroundService so the QS tile stays in sync.
                "setCrashMonitorActive" -> {
                    val active = call.arguments as? Boolean ?: false
                    CrashMonitorPrefs.setActive(this, active)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        deliverSosFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverSosFromIntent(intent)
    }

    private fun deliverSosFromIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("hardware_sos", false) == true) {
            methodChannel?.invokeMethod("triggerSOS", null)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastPressTime > 2000) {
            volumeUpPresses = 0
            volumeDownPresses = 0
        }
        lastPressTime = currentTime

        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            volumeUpPresses++
            checkSosTrigger()
            return true
        } else if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            volumeDownPresses++
            checkSosTrigger()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun checkSosTrigger() {
        if (volumeUpPresses >= 3 && volumeDownPresses >= 3) {
            methodChannel?.invokeMethod("triggerSOS", null)
            volumeUpPresses = 0
            volumeDownPresses = 0
        }
    }
}
