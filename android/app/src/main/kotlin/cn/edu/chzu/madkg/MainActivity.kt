package cn.edu.chzu.madkg

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val SCREEN_CAPTURE_CHANNEL = "madkg/screen_capture"
        const val SCREEN_CAPTURE_EVENTS = "madkg/screen_capture_events"
        private const val REQUEST_CODE_SCREEN_CAPTURE = 1001
    }

    private var screenCapturePlugin: ScreenCapturePlugin? = null
    private var captureEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        screenCapturePlugin = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ScreenCapturePlugin(this, flutterEngine)
        } else {
            null
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        if (screenCapturePlugin == null) {
                            result.error("UNSUPPORTED", "Android 10+ required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = screenCapturePlugin!!.createCaptureIntent()
                            startActivityForResult(intent, REQUEST_CODE_SCREEN_CAPTURE)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INTENT_ERROR", "无法创建屏幕捕获意图: ${e.message}", null)
                        }
                    }
                    "stop" -> {
                        try {
                            screenCapturePlugin?.stop()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    captureEventSink = events
                    screenCapturePlugin?.setEventSink(events)
                }
                override fun onCancel(arguments: Any?) {
                    captureEventSink = null
                    screenCapturePlugin?.setEventSink(null)
                }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode == RESULT_OK && data != null) {
                screenCapturePlugin?.onCaptureResult(resultCode, data)
                // 授权成功后最小化应用，让学生演示自己的应用
                moveTaskToBack(true)
            } else {
                captureEventSink?.error("PERMISSION_DENIED", "用户拒绝屏幕捕获权限", null)
            }
        }
    }

    override fun onDestroy() {
        try {
            screenCapturePlugin?.stop()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
