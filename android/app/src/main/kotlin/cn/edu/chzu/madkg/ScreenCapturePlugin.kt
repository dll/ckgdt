package cn.edu.chzu.madkg

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.DisplayMetrics
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream

class ScreenCapturePlugin(
    private val activity: Activity,
    private val flutterEngine: FlutterEngine
) {
    private val projectionManager =
        activity.getSystemService(Activity.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var handlerThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var eventSink: EventChannel.EventSink? = null
    private var isRunning = false

    private val metrics: DisplayMetrics
        get() {
            val m = DisplayMetrics()
            val wm = activity.getSystemService(Activity.WINDOW_SERVICE) as WindowManager
            wm.defaultDisplay.getRealMetrics(m)
            return m
        }

    fun setEventSink(sink: EventChannel.EventSink?) { eventSink = sink }

    fun createCaptureIntent(): Intent = projectionManager.createScreenCaptureIntent()

    fun onCaptureResult(resultCode: Int, data: Intent) {
        if (resultCode != Activity.RESULT_OK) {
            eventSink?.error("PERMISSION_DENIED", "用户拒绝屏幕捕获", null)
            return
        }

        mediaProjection = projectionManager.getMediaProjection(resultCode, data)
        startCapture()
    }

    private fun startCapture() {
        if (isRunning) return
        isRunning = true

        val dm = metrics
        val density = dm.densityDpi
        val width = dm.widthPixels
        val height = dm.heightPixels

        handlerThread = HandlerThread("ScreenCapture").apply { start() }
        backgroundHandler = Handler(handlerThread!!.looper)

        imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 2)
        imageReader!!.setOnImageAvailableListener({ reader ->
            if (!isRunning) return@setOnImageAvailableListener
            try {
                val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                val buffer = image.planes[0].buffer
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)
                image.close()
                eventSink?.success(bytes)
            } catch (e: Exception) {
                eventSink?.error("CAPTURE_ERROR", e.message, null)
            }
        }, backgroundHandler)

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "DefenseScreenCapture",
            width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface,
            null,
            backgroundHandler
        )

        eventSink?.success(null) // 仅通知已启动
    }

    fun stop() {
        isRunning = false
        try { virtualDisplay?.release() } catch (_: Exception) {}
        try { imageReader?.close() } catch (_: Exception) {}
        try { mediaProjection?.stop() } catch (_: Exception) {}
        try { handlerThread?.quitSafely() } catch (_: Exception) {}
        virtualDisplay = null
        imageReader = null
        mediaProjection = null
        handlerThread = null
        backgroundHandler = null
    }
}
