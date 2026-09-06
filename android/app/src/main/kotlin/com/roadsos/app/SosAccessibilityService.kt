package com.roadsos.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.view.KeyEvent

/**
 * Global volume-pattern SOS when the app is not in the foreground.
 * Requires user opt-in under Settings → Accessibility.
 *
 * Uses the same gesture as [MainActivity] (3× volume up + 3× volume down within 2 seconds).
 */
class SosAccessibilityService : AccessibilityService() {

    private var volumeUpPresses = 0
    private var volumeDownPresses = 0
    private var lastPressTime: Long = 0

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = serviceInfo
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        serviceInfo = info
    }

    override fun onAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) {
            return super.onKeyEvent(event)
        }

        val currentTime = System.currentTimeMillis()
        if (currentTime - lastPressTime > 2000L) {
            volumeUpPresses = 0
            volumeDownPresses = 0
        }
        lastPressTime = currentTime

        when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                volumeUpPresses++
                checkTrigger()
                return true
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                volumeDownPresses++
                checkTrigger()
                return true
            }
        }
        return super.onKeyEvent(event)
    }

    private fun checkTrigger() {
        if (volumeUpPresses >= 3 && volumeDownPresses >= 3) {
            volumeUpPresses = 0
            volumeDownPresses = 0
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("hardware_sos", true)
            }
            startActivity(intent)
        }
    }
}
