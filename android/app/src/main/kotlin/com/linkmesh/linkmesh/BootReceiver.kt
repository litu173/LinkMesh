package com.linkmesh.linkmesh

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/** Restarts background relaying after a reboot or an app update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return
        // Only once the user has set the app up and left background relay on.
        if (!Prefs.wasStarted(context) || !Prefs.isEnabled(context)) return
        if (!hasBluetoothPermissions(context)) return
        try {
            MeshService.start(context, withLocation = false)
        } catch (e: Exception) {
            Log.w("LinkMesh", "Could not start mesh after boot: $e")
        }
    }

    private fun hasBluetoothPermissions(context: Context): Boolean {
        val needed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            )
        } else {
            // Scanning on Android 11 and below needs location.
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return needed.all {
            context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }
}
