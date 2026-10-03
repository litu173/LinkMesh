package com.linkmesh.linkmesh

import android.content.Context

/** Native-side settings, readable before any Dart code runs (e.g. at boot). */
object Prefs {
    private const val FILE = "linkmesh_native"
    private const val KEY_ENABLED = "background_enabled"
    private const val KEY_STARTED = "was_started"

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Background relay toggle. On by default. */
    fun isEnabled(context: Context) = prefs(context).getBoolean(KEY_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) =
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()

    /** True once the mesh has been started from the app with permissions granted. */
    fun wasStarted(context: Context) = prefs(context).getBoolean(KEY_STARTED, false)

    fun markStarted(context: Context) =
        prefs(context).edit().putBoolean(KEY_STARTED, true).apply()
}
