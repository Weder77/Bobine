package io.github.weder77.bobine

import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bobine/app").setMethodCallHandler { call, result ->
            when (call.method) {
                // Retour on Accueil: Bobine goes behind, as with Home, instead of
                // finishing; it comes back at once, where it was.
                "toBackground" -> result.success(moveTaskToBack(true))
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // The player's threads (mpv, through media_kit) outlive the Flutter
        // engine: a new engine in this same process crashes while cleaning
        // them up (SIGSEGV in "mpv core"). A fresh process has none.
        if (!isChangingConfigurations) Process.killProcess(Process.myPid())
    }
}
