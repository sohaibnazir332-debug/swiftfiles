package com.swiftfiles.swift_files

import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Storage indicator ke liye: total aur khali jagah Flutter ko batata hai.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "swift_files/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "stats") {
                    try {
                        val st = StatFs(Environment.getExternalStorageDirectory().path)
                        result.success(listOf(st.totalBytes, st.availableBytes))
                    } catch (e: Exception) {
                        result.error("ERR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
