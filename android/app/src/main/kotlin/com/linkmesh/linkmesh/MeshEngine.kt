package com.linkmesh.linkmesh

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * One Flutter engine for the whole process, shared by the activity and the
 * background service. The mesh (BLE, router, database) lives in this engine's
 * Dart isolate, so it keeps running after the activity is closed, as long as
 * [MeshService] keeps the process alive.
 */
object MeshEngine {
    private const val ENGINE_ID = "mesh"
    private const val CHANNEL = "linkmesh/service"

    private var channel: MethodChannel? = null

    /** Peer whose chat should open next time the UI is shown (from a notification tap). */
    @Volatile
    var pendingChat: String? = null

    fun ensure(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val app = context.applicationContext
        Notifier.ensureChannels(app)
        // Plugins are registered automatically by the constructor.
        val engine = FlutterEngine(app)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(ServiceChannel(app))
        }
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    fun notifyDart(method: String, args: Any? = null) {
        channel?.invokeMethod(method, args)
    }
}
