package com.linkmesh.linkmesh

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Dart -> native calls on the `linkmesh/service` channel. */
class ServiceChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    Prefs.markStarted(context)
                    Prefs.setEnabled(context, true)
                    MeshService.start(context, call.argument<Boolean>("withLocation") ?: false)
                    result.success(true)
                }
                "stop" -> {
                    Prefs.setEnabled(context, false)
                    MeshService.stop(context)
                    result.success(true)
                }
                "isEnabled" -> result.success(Prefs.isEnabled(context))
                "isRunning" -> result.success(MeshService.running)
                "setStatus" -> {
                    Notifier.updateServiceNotification(context, call.argument<String>("text") ?: "")
                    result.success(null)
                }
                "notifyMessage" -> {
                    Notifier.message(
                        context,
                        call.argument<String>("peerId")!!,
                        call.argument<String>("title") ?: "",
                        call.argument<String>("body") ?: "",
                    )
                    result.success(null)
                }
                "notifySos" -> {
                    Notifier.sos(
                        context,
                        call.argument<String>("senderId")!!,
                        call.argument<String>("title") ?: "",
                        call.argument<String>("body") ?: "",
                        call.argument<Boolean>("alert") ?: true,
                    )
                    result.success(null)
                }
                "cancel" -> {
                    Notifier.cancel(context, call.argument<String>("key")!!)
                    result.success(null)
                }
                "playSound" -> {
                    Notifier.play(context, call.argument<String>("kind") ?: "message")
                    result.success(null)
                }
                "takePendingChat" -> {
                    val peer = MeshEngine.pendingChat
                    MeshEngine.pendingChat = null
                    result.success(peer)
                }
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                "isIgnoringBatteryOptimizations" -> {
                    val pm = context.getSystemService(PowerManager::class.java)
                    result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
                }
                "requestBatteryExemption" -> {
                    requestBatteryExemption()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("linkmesh", e.message, null)
        }
    }

    // Side-loaded test builds only; Play policy restricts this permission.
    @SuppressLint("BatteryLife")
    private fun requestBatteryExemption() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
