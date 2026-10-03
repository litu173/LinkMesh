package com.linkmesh.linkmesh

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // Attach to the process-wide engine instead of creating one per activity,
    // and keep it alive when the activity is closed so the mesh keeps running.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        MeshEngine.ensure(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        capturePendingChat(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        capturePendingChat(intent)
    }

    private fun capturePendingChat(intent: Intent?) {
        intent?.getStringExtra(Notifier.EXTRA_PEER)?.let { MeshEngine.pendingChat = it }
    }
}
