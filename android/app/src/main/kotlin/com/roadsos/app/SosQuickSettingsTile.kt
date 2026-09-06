package com.roadsos.app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import id.flutter.flutter_background_service.FlutterBackgroundServicePlugin
import org.json.JSONObject

// SharedPreferences written by both the tile and Flutter (via MainActivity
// MethodChannel "setCrashMonitorActive") to keep crash-monitor state in sync.
internal object CrashMonitorPrefs {
    const val FILE = "roadsos_quick_settings"
    const val KEY_ACTIVE = "crash_monitor_enabled"

    fun isActive(ctx: Context): Boolean =
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_ACTIVE, false)

    fun setActive(ctx: Context, active: Boolean) =
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ACTIVE, active).apply()
}

// Quick Settings tile for RoadSOS crash monitoring (Android 7.0+, API 24).
// Green dot  = STATE_ACTIVE  = monitoring on.
// Grey dot   = STATE_INACTIVE = monitoring paused.
@RequiresApi(Build.VERSION_CODES.N)
class SosQuickSettingsTile : TileService() {

    private val bgServiceClass = "id.flutter.flutter_background_service.BackgroundService"

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        val enable = !CrashMonitorPrefs.isActive(this)
        CrashMonitorPrefs.setActive(this, enable)
        if (enable) startCrashMonitor() else stopCrashMonitor()
        refreshTile()
    }

    private fun startCrashMonitor() {
        val intent = Intent().setClassName(packageName, bgServiceClass)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        // Delay 500 ms so the service's onCreate() registers its Pipe listener
        // before we dispatch start_crash_monitor (same path as
        // EmergencyBackgroundService.startCrashMonitor() → servicePipe.invoke).
        Handler(Looper.getMainLooper()).postDelayed({
            sendCommand("start_crash_monitor")
        }, 500)
    }

    private fun stopCrashMonitor() {
        // Send stop_crash_monitor without stopping the service so safe-walk
        // timers and heartbeat continue (same path as stopCrashMonitor()).
        sendCommand("stop_crash_monitor")
    }

    // Delivers a command to the flutter_background_service background Dart
    // isolate via the plugin's static Pipe — the same mechanism used by
    // FlutterBackgroundService().invoke() from the main Dart isolate.
    private fun sendCommand(method: String) {
        FlutterBackgroundServicePlugin.servicePipe.invoke(
            JSONObject().put("method", method).put("args", JSONObject.NULL)
        )
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val active = CrashMonitorPrefs.isActive(this)
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(if (active) R.string.qs_tile_label_on else R.string.qs_tile_label_off)
        tile.contentDescription = getString(
            if (active) R.string.qs_tile_desc_on else R.string.qs_tile_desc_off
        )
        tile.updateTile()
    }
}
