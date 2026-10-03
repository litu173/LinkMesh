package com.linkmesh.linkmesh

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that keeps the process (and so the mesh engine) alive
 * while the app is closed, so this phone keeps receiving and relaying.
 */
class MeshService : Service() {
    companion object {
        const val NOTIFICATION_ID = 1
        const val ACTION_STOP = "com.linkmesh.linkmesh.STOP_MESH"
        private const val EXTRA_LOCATION = "with_location"
        private const val TAG = "LinkMesh"

        @Volatile
        var running = false
            private set

        var statusText = "Listening for nearby devices"

        fun start(context: Context, withLocation: Boolean) {
            val intent = Intent(context, MeshService::class.java)
                .putExtra(EXTRA_LOCATION, withLocation)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MeshService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Prefs.setEnabled(this, false)
            MeshEngine.notifyDart("serviceStopped")
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        // Location type lets SOS read GPS while closed; it is only allowed
        // when started from the foreground with location granted, so fall
        // back to connectedDevice alone if the system refuses it.
        val withLocation = intent?.getBooleanExtra(EXTRA_LOCATION, false) ?: false
        val notification = Notifier.serviceNotification(this, statusText)
        val started = tryStartForeground(notification, serviceTypes(withLocation)) ||
            (withLocation && tryStartForeground(notification, serviceTypes(false)))
        if (!started) {
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        MeshEngine.ensure(this)
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun serviceTypes(withLocation: Boolean): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return 0
        var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        if (withLocation) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        return types
    }

    private fun tryStartForeground(notification: android.app.Notification, types: Int): Boolean =
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, types)
            true
        } catch (e: Exception) {
            Log.w(TAG, "startForeground(types=$types) refused: $e")
            false
        }
}
