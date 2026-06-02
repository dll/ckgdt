package cn.edu.chzu.madkg

import android.content.Intent
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
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

    private val screenCaptureResult = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK && result.data != null) {
            screenCapturePlugin?.onCaptureResult(result.resultCode, result.data!!)
        } else {
            captureEventSink?.error("PERMISSION_DENIED", "用户拒绝屏幕捕获权限", null)
        }
    }

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
                        val intent = screenCapturePlugin!!.createCaptureIntent()
                        screenCaptureResult.launch(intent)
                        result.success(true)
                    }
                    "stop" -> {
                        screenCapturePlugin?.stop()
                        result.success(true)
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

    override fun onDestroy() {
        screenCapturePlugin?.stop()
        super.onDestroy()
    }
}
