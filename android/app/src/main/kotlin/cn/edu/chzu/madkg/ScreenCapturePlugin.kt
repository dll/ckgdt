package cn.edu.chzu.madkg

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
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
import java.nio.ByteBuffer

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

    // 复用缓冲，避免每帧分配（10+ fps 下减少 GC 压力）
    private var nv21Buffer: ByteArray? = null
    private val jpegStream = ByteArrayOutputStream()

    private val metrics: DisplayMetrics
        get() {
            val m = DisplayMetrics()
            val wm = activity.getSystemService(Activity.WINDOW_SERVICE) as WindowManager
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(m)
            return m
        }

    fun setEventSink(sink: EventChannel.EventSink?) { eventSink = sink }

    fun createCaptureIntent(): Intent = projectionManager.createScreenCaptureIntent()

    fun onCaptureResult(resultCode: Int, data: Intent) {
        if (resultCode != Activity.RESULT_OK) {
            eventSink?.error("PERMISSION_DENIED", "\u7528\u6237\u62d2\u7edd\u5c4f\u5e55\u6355\u83b7", null)
            return
        }
        try {
            mediaProjection = projectionManager.getMediaProjection(resultCode, data)
            startCapture()
        } catch (e: Exception) {
            eventSink?.error("PROJECTION_ERROR", "MediaProjection\u521d\u59cb\u5316\u5931\u8d25: ${e.message}", null)
            mediaProjection = null
        }
    }

    private fun startCapture() {
        if (isRunning) return
        isRunning = true

        try {
            val dm = metrics
            val density = dm.densityDpi
            val width = dm.widthPixels
            val height = dm.heightPixels

            handlerThread = HandlerThread("ScreenCapture").apply { start() }
            backgroundHandler = Handler(handlerThread!!.looper)

            val handler = backgroundHandler ?: run {
                eventSink?.error("THREAD_ERROR", "\u540e\u53f0\u7ebf\u7a0b\u521b\u5efa\u5931\u8d25", null)
                stop()
                return
            }

            // 优先尝试 JPEG 格式（直接输出，无需转换）；不支持时回退 YUV
            try {
                imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 4)
            } catch (e: Exception) {
                // JPEG 不支持，用 YUV（保留兼容代码但不折腾转换）
            }
            if (imageReader == null) {
                imageReader = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 4)
            }

            val isJpeg = imageReader!!.imageFormat == ImageFormat.JPEG
            imageReader!!.setOnImageAvailableListener({ reader ->
                if (!isRunning) return@setOnImageAvailableListener
                try {
                    val image: Image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                    try {
                        if (isJpeg) {
                            val buf = image.planes[0].buffer
                            val bytes = ByteArray(buf.remaining())
                            buf.get(bytes)
                            image.close()
                            eventSink?.success(bytes)
                        } else {
                            val bytes = imageToJpeg(image)
                            image.close()
                            if (bytes != null) eventSink?.success(bytes)
                        }
                    } catch (e: Exception) {
                        try { image.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {}
            }, handler)

            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "DefenseScreenCapture",
                width, height, density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader!!.surface,
                null,
                handler
            )

            if (virtualDisplay == null) {
                eventSink?.error("VD_ERROR", "VirtualDisplay\u521b\u5efa\u5931\u8d25", null)
                stop()
                return
            }

            eventSink?.success(null)
        } catch (e: Exception) {
            eventSink?.error("CAPTURE_ERROR", "屏幕捕获启动失败: ${e.message}", null)
            stop()
        }
    }

    private fun imageToJpeg(image: Image): ByteArray? {
        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer

        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()

        val needed = ySize + uSize + vSize
        var nv21 = nv21Buffer
        if (nv21 == null || nv21.size != needed) {
            nv21 = ByteArray(needed)
            nv21Buffer = nv21
        }

        yBuffer.get(nv21, 0, ySize)

        // NV21: VU interleaved (NOT separate V + U blocks)
        var pos = ySize
        val count = minOf(vSize, uSize)
        for (i in 0 until count) {
            nv21[pos++] = vBuffer.get()
            nv21[pos++] = uBuffer.get()
        }

        val yuvImage = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
        jpegStream.reset()
        yuvImage.compressToJpeg(Rect(0, 0, image.width, image.height), 75, jpegStream)
        jpegStream.flush()
        return jpegStream.toByteArray()
    }

    fun stop() {
        isRunning = false
        try {
            virtualDisplay?.release()
            virtualDisplay = null
        } catch (_: Exception) {}
        try {
            imageReader?.close()
            imageReader = null
        } catch (_: Exception) {}
        try {
            mediaProjection?.stop()
            mediaProjection = null
        } catch (_: Exception) {}
        try {
            handlerThread?.quitSafely()
            handlerThread = null
            backgroundHandler = null
        } catch (_: Exception) {}
    }
}
