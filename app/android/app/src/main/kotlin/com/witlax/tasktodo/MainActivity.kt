package com.witlax.tasktodo

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.witlax.tasktodo/focus"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val title = call.argument<String>("title") ?: "专注中"
                        val endAt = call.argument<Long>("endAt") ?: 0L
                        val intent = Intent(this, FocusService::class.java).apply {
                            action = FocusService.ACTION_START
                            putExtra(FocusService.EXTRA_TITLE, title)
                            putExtra(FocusService.EXTRA_END_AT, endAt)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stop" -> {
                        startService(
                            Intent(this, FocusService::class.java).apply {
                                action = FocusService.ACTION_STOP
                            }
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
