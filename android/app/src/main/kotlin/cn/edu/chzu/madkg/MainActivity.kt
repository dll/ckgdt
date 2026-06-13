package cn.edu.chzu.madkg

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {
    companion object {
        const val SCREEN_CAPTURE_CHANNEL = "madkg/screen_capture"
        const val SCREEN_CAPTURE_EVENTS = "madkg/screen_capture_events"
        const val CAMERA_CAPTURE_EVENTS = "madkg/camera_capture_events"
        private const val REQUEST_CODE_SCREEN_CAPTURE = 1001
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingServerUrl: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.error("UNSUPPORTED", "Android 10+ required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                                as MediaProjectionManager
                            // 保存 result，授权对话框返回后再回 success/error
                            pendingResult = result
                            pendingServerUrl = call.argument<String>("serverUrl")
                            startActivityForResult(
                                mgr.createScreenCaptureIntent(), REQUEST_CODE_SCREEN_CAPTURE)
                        } catch (e: Exception) {
                            pendingResult = null
                            pendingServerUrl = null
                            result.error("INTENT_ERROR", "无法创建屏幕捕获意图: ${e.message}", null)
                        }
                    }
                    "stop" -> {
                        try {
                            val intent = Intent(this, ScreenCaptureService::class.java)
                                .apply { action = ScreenCaptureService.ACTION_STOP }
                            startService(intent)
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
                    CaptureSinks.screenSink = if (events != null) WeakReference(events) else null
                }
                override fun onCancel(arguments: Any?) {
                    CaptureSinks.screenSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_CAPTURE_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    CaptureSinks.cameraSink = if (events != null) WeakReference(events) else null
                }
                override fun onCancel(arguments: Any?) {
                    CaptureSinks.cameraSink = null
                }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE_SCREEN_CAPTURE) return
        if (resultCode == RESULT_OK && data != null) {
            val directUpload = !pendingServerUrl.isNullOrBlank()
            // 启动前台服务托管录屏+摄像头；随后退到后台，避免 MediaProjection
            // 录到本答辩页自身造成递归画面。服务独立于 Activity 生命周期。
            val intent = Intent(this, ScreenCaptureService::class.java).apply {
                action = ScreenCaptureService.ACTION_START
                putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
                putExtra(ScreenCaptureService.EXTRA_SERVER_URL, pendingServerUrl ?: "")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            pendingResult?.success(true)
            if (directUpload) {
                Handler(Looper.getMainLooper()).postDelayed({
                    moveTaskToBack(true)
                }, 600)
            }
        } else {
            CaptureSinks.screenSink?.get()?.error("PERMISSION_DENIED", "用户拒绝屏幕捕获权限", null)
            pendingResult?.success(false)
        }
        pendingServerUrl = null
        pendingResult = null
    }

    override fun onDestroy() {
        try {
            val intent = Intent(this, ScreenCaptureService::class.java)
                .apply { action = ScreenCaptureService.ACTION_STOP }
            startService(intent)
        } catch (e: Exception) {}
        super.onDestroy()
    }
}
