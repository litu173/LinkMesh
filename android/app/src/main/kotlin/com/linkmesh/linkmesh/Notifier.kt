package com.linkmesh.linkmesh

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/** Notification channels, notifications and in-app sounds. */
object Notifier {
    const val EXTRA_PEER = "peer_id"

    // Channel sounds can't change after creation; bump the id to ship a new sound.
    private const val CH_SERVICE = "mesh_service"
    private const val CH_MESSAGES = "messages_v1"
    private const val CH_SOS = "sos_v1"

    private val messageAttrs = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    // Alarm usage: an SOS is heard even when the ringer is on silent.
    private val sosAttrs = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    // "... --- ..." as a vibration pattern.
    private val sosVibration = longArrayOf(
        0, 120, 100, 120, 100, 120, 300,
        360, 100, 360, 100, 360, 300,
        120, 100, 120, 100, 120,
    )
    private val messageVibration = longArrayOf(0, 60, 80, 60)

    private fun rawUri(context: Context, resId: Int): Uri =
        Uri.parse("android.resource://${context.packageName}/$resId")

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CH_SERVICE, "Background relay", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while LinkMesh relays messages with the app closed"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_MESSAGES, "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "New messages from nearby devices"
                setSound(rawUri(context, R.raw.message_chime), messageAttrs)
                enableVibration(true)
                vibrationPattern = messageVibration
                lightColor = Color.rgb(14, 124, 102)
                enableLights(true)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_SOS, "SOS alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Emergency broadcasts from people nearby"
                setSound(rawUri(context, R.raw.sos_alert), sosAttrs)
                enableVibration(true)
                vibrationPattern = sosVibration
                lightColor = Color.RED
                enableLights(true)
                setBypassDnd(true) // only takes effect if the user allows it
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
        )
    }

    private fun openAppIntent(context: Context, peerId: String?, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (peerId != null) putExtra(EXTRA_PEER, peerId)
        }
        return PendingIntent.getActivity(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun serviceNotification(context: Context, text: String): Notification {
        val stop = PendingIntent.getService(
            context, 1,
            Intent(context, MeshService::class.java).setAction(MeshService.ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(context, CH_SERVICE)
            .setSmallIcon(R.drawable.ic_stat_linkmesh)
            .setContentTitle("LinkMesh is relaying")
            .setContentText(text)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openAppIntent(context, null, 0))
            .addAction(0, "Stop", stop)
            .build()
    }

    fun updateServiceNotification(context: Context, text: String) {
        MeshService.statusText = text
        if (!MeshService.running) return
        post(context, MeshService.NOTIFICATION_ID, serviceNotification(context, text))
    }

    fun message(context: Context, peerId: String, title: String, body: String) {
        val id = "msg:$peerId".hashCode()
        val builder = NotificationCompat.Builder(context, CH_MESSAGES)
            .setSmallIcon(R.drawable.ic_stat_linkmesh)
            .setColor(Color.rgb(14, 124, 102))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(context, peerId, id))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setSound(rawUri(context, R.raw.message_chime))
                .setVibrate(messageVibration)
        }
        post(context, id, builder.build())
    }

    /** [alert] false updates an existing SOS silently (repeat broadcasts). */
    fun sos(context: Context, senderId: String, title: String, body: String, alert: Boolean) {
        val id = "sos:$senderId".hashCode()
        val builder = NotificationCompat.Builder(context, CH_SOS)
            .setSmallIcon(R.drawable.ic_stat_linkmesh)
            .setColor(Color.RED)
            .setColorized(true)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(!alert)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(context, "sos", id))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setSound(rawUri(context, R.raw.sos_alert), android.media.AudioManager.STREAM_ALARM)
                .setVibrate(sosVibration)
        }
        // Re-posting with onlyAlertOnce=false only re-alerts if it was gone.
        if (alert) NotificationManagerCompat.from(context).cancel(id)
        post(context, id, builder.build())
    }

    fun cancel(context: Context, key: String) {
        NotificationManagerCompat.from(context).cancel(key.hashCode())
    }

    @SuppressLint("MissingPermission")
    private fun post(context: Context, id: Int, notification: Notification) {
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return
        try {
            nm.notify(id, notification)
        } catch (e: SecurityException) {
            Log.w("LinkMesh", "Notification blocked: $e")
        }
    }

    /** Plays a sound directly, for events while the app is on screen. */
    fun play(context: Context, kind: String) {
        val (resId, attrs) = when (kind) {
            "sos" -> R.raw.sos_alert to sosAttrs
            else -> R.raw.message_chime to messageAttrs
        }
        try {
            MediaPlayer().apply {
                setAudioAttributes(attrs)
                setDataSource(context, rawUri(context, resId))
                setOnCompletionListener { it.release() }
                setOnErrorListener { mp, _, _ -> mp.release(); true }
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.w("LinkMesh", "Could not play $kind: $e")
        }
    }
}
