package cn.edu.chzu.madkg

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.PixelFormat
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
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

/// 进程内回调持有者：插件设置 EventSink，服务推帧时取用。
/// 用 WeakReference 防止服务比插件活得久造成泄漏。
object CaptureSinks {
    var screenSink: WeakReference<EventChannel.EventSink>? = null
    var cameraSink: WeakReference<EventChannel.EventSink>? = null
}

/// 答辩直播前台服务：托管 MediaProjection(整屏录制) + CameraX(前置人脸)，
/// 使二者脱离 Flutter Activity 生命周期，App 切后台演示其他应用时仍持续推帧。
class ScreenCaptureService : Service(), LifecycleOwner {

    companion object {
        const val ACTION_START = "cn.edu.chzu.madkg.action.START_CAPTURE"
        const val ACTION_STOP = "cn.edu.chzu.madkg.action.STOP_CAPTURE"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_SERVER_URL = "serverUrl"
        private const val CHANNEL_ID = "defense_capture"
        private const val NOTIFICATION_ID = 0x5AD
        private const val SCREEN_MIN_INTERVAL_MS = 180L
        private const val CAMERA_MIN_INTERVAL_MS = 330L
    }

    private val lifecycleRegistry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = lifecycleRegistry

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var handlerThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var serverUrl: String = ""
    private var lastScreenPostAt = 0L
    private var lastCameraPostAt = 0L

    private var cameraProvider: ProcessCameraProvider? = null
    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private val networkExecutor = Executors.newFixedThreadPool(2)
    @Volatile private var screenPostInFlight = false
    @Volatile private var cameraPostInFlight = false

    // 复用缓冲，避免每帧分配
    private val screenJpeg = ByteArrayOutputStream()
    private var cameraNv21: ByteArray? = null
    private val cameraJpeg = ByteArrayOutputStream()

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            stopEverything()
            stopSelf()
        }
    }

    override fun onCreate() {
        super.onCreate()
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopEverything()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: 0
                val data = intent?.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
                serverUrl = intent?.getStringExtra(EXTRA_SERVER_URL)?.trimEnd('/') ?: ""
                startCapture(resultCode, data)
            }
        }
        return START_NOT_STICKY
    }

    private fun startCapture(resultCode: Int, data: Intent?) {
        // 必须先 startForeground（含 type），再 getMediaProjection（Android 14+ 强制）
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        } else 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, buildNotification(), type)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }

        if (data == null) {
            screenError("NO_PROJECTION_DATA", "缺少屏幕捕获授权数据")
            stopSelf()
            return
        }

        try {
            lastScreenPostAt = 0L
            lastCameraPostAt = 0L
            val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = mgr.getMediaProjection(resultCode, data)
            // createVirtualDisplay 前必须注册回调（targetSdk 34+ 不注册抛异常）
            mediaProjection?.registerCallback(projectionCallback, backgroundHandler ?: mainHandler())
            startScreenCapture()
            startCameraCapture()
            // null 事件通知 Dart 端启动成功
            CaptureSinks.screenSink?.get()?.success(null)
        } catch (e: Exception) {
            screenError("PROJECTION_ERROR", "MediaProjection 启动失败: ${e.message}")
            stopEverything()
            stopSelf()
        }
    }

    // ── 屏幕录制（MediaProjection + ImageReader） ──────────────────────
    private fun startScreenCapture() {
        val dm = metrics()
        val width = dm.widthPixels
        val height = dm.heightPixels
        val density = dm.densityDpi

        handlerThread = HandlerThread("DefenseScreenCapture").apply { start() }
        backgroundHandler = Handler(handlerThread!!.looper)

        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader = reader

        reader.setOnImageAvailableListener({ r ->
            val image: Image = try { r.acquireLatestImage() } catch (e: Exception) { null } ?: return@setOnImageAvailableListener
            try {
                if (!shouldSendScreen()) return@setOnImageAvailableListener
                val bytes = rgbaToJpeg(image, screenJpeg)
                if (bytes != null) {
                    if (serverUrl.isNotEmpty()) {
                        postFrameAsync("/frame/phone", bytes, isScreen = true)
                    } else {
                        CaptureSinks.screenSink?.get()?.success(bytes)
                    }
                }
            } catch (e: Exception) {
                // 单帧失败忽略，继续下一帧
            } finally {
                try { image.close() } catch (e: Exception) {}
            }
        }, backgroundHandler)

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "DefenseScreenCapture", width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface, null, backgroundHandler
        )
    }

    // ── 前置摄像头（CameraX ImageAnalysis，无需预览 Surface） ──────────
    private fun startCameraCapture() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener(Runnable {
            try {
                val provider = future.get()
                cameraProvider = provider
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(cameraExecutor, ImageAnalysis.Analyzer { proxy -> onCameraFrame(proxy) })
                lifecycleRegistry.currentState = Lifecycle.State.STARTED
                provider.unbindAll()
                provider.bindToLifecycle(this, CameraSelector.DEFAULT_FRONT_CAMERA, analysis)
            } catch (e: Exception) {
                // 摄像头不可用不应中断录屏
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun onCameraFrame(proxy: ImageProxy) {
        try {
            val bytes = imageProxyToJpeg(proxy)
            if (bytes != null && shouldSendCamera()) {
                if (serverUrl.isNotEmpty()) {
                    postFrameAsync("/frame/camera", bytes, isScreen = false)
                } else {
                    CaptureSinks.cameraSink?.get()?.success(bytes)
                }
            }
        } catch (e: Exception) {
            // 忽略单帧
        } finally {
            proxy.close()
        }
    }

    // ── YUV_420_888 → NV21 → JPEG（复用缓冲） ─────────────────────────
    private fun cameraBufFor(size: Int): ByteArray {
        var b = cameraNv21
        if (b == null || b.size != size) { b = ByteArray(size); cameraNv21 = b }
        return b
    }

    private fun shouldSendScreen(): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastScreenPostAt < SCREEN_MIN_INTERVAL_MS) return false
        lastScreenPostAt = now
        return true
    }

    private fun shouldSendCamera(): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastCameraPostAt < CAMERA_MIN_INTERVAL_MS) return false
        lastCameraPostAt = now
        return true
    }

    private fun postFrame(path: String, bytes: ByteArray) {
        var conn: HttpURLConnection? = null
        try {
            conn = URL("$serverUrl$path").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 1200
            conn.readTimeout = 1200
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "image/jpeg")
            conn.outputStream.use { it.write(bytes) }
            val code = conn.responseCode
            val stream = if (code >= 400) conn.errorStream else conn.inputStream
            try { stream?.close() } catch (e: Exception) {}
        } catch (e: Exception) {
            // 单帧上传失败忽略，后续帧继续尝试。
        } finally {
            try { conn?.disconnect() } catch (e: Exception) {}
        }
    }

    private fun postFrameAsync(path: String, bytes: ByteArray, isScreen: Boolean) {
        if (isScreen) {
            if (screenPostInFlight) return
            screenPostInFlight = true
        } else {
            if (cameraPostInFlight) return
            cameraPostInFlight = true
        }
        networkExecutor.execute {
            try {
                postFrame(path, bytes)
            } finally {
                if (isScreen) {
                    screenPostInFlight = false
                } else {
                    cameraPostInFlight = false
                }
            }
        }
    }

    private fun rgbaToJpeg(image: Image, out: ByteArrayOutputStream): ByteArray? {
        val plane = image.planes.firstOrNull() ?: return null
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        if (pixelStride <= 0 || rowStride <= 0) return null
        val rowWidth = rowStride / pixelStride
        if (rowWidth < image.width) return null
        val bitmap = Bitmap.createBitmap(rowWidth, image.height, Bitmap.Config.ARGB_8888)
        bitmap.copyPixelsFromBuffer(buffer)
        val cropped = if (rowWidth == image.width) {
            bitmap
        } else {
            Bitmap.createBitmap(bitmap, 0, 0, image.width, image.height)
        }
        val maxWidth = 720
        val encoded = if (cropped.width > maxWidth) {
            val scaledHeight = (cropped.height * (maxWidth.toFloat() / cropped.width)).toInt()
            val scaled = Bitmap.createScaledBitmap(cropped, maxWidth, scaledHeight, true)
            out.reset()
            scaled.compress(Bitmap.CompressFormat.JPEG, 55, out)
            scaled.recycle()
            out.toByteArray()
        } else {
            out.reset()
            cropped.compress(Bitmap.CompressFormat.JPEG, 55, out)
            out.toByteArray()
        }
        if (cropped !== bitmap) cropped.recycle()
        bitmap.recycle()
        return encoded
    }

    private fun imageProxyToJpeg(proxy: ImageProxy): ByteArray? {
        val image = proxy.image ?: return null
        val nv21 = yuv420ToNv21(image, ::cameraBufFor)
        val yuv = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
        cameraJpeg.reset()
        yuv.compressToJpeg(Rect(0, 0, image.width, image.height), 70, cameraJpeg)
        val raw = cameraJpeg.toByteArray()
        val rotation = proxy.imageInfo.rotationDegrees
        if (rotation == 0) return raw

        val bitmap = BitmapFactory.decodeByteArray(raw, 0, raw.size) ?: return raw
        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        cameraJpeg.reset()
        rotated.compress(Bitmap.CompressFormat.JPEG, 70, cameraJpeg)
        if (rotated !== bitmap) rotated.recycle()
        bitmap.recycle()
        return cameraJpeg.toByteArray()
    }

    private fun yuv420ToNv21(image: Image, bufFor: (Int) -> ByteArray): ByteArray {
        val width = image.width
        val height = image.height
        val frameSize = width * height
        val output = bufFor(frameSize + frameSize / 2)

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        copyPlane(
            yPlane.buffer,
            yPlane.rowStride,
            yPlane.pixelStride,
            width,
            height,
            output,
            0,
            1
        )

        val uBuffer = uPlane.buffer.duplicate()
        val vBuffer = vPlane.buffer.duplicate()
        val chromaWidth = width / 2
        val chromaHeight = height / 2
        var offset = frameSize
        for (row in 0 until chromaHeight) {
            val uRow = row * uPlane.rowStride
            val vRow = row * vPlane.rowStride
            for (col in 0 until chromaWidth) {
                val uIndex = uRow + col * uPlane.pixelStride
                val vIndex = vRow + col * vPlane.pixelStride
                if (offset + 1 >= output.size ||
                    uIndex >= uBuffer.limit() ||
                    vIndex >= vBuffer.limit()
                ) {
                    return output
                }
                output[offset++] = vBuffer.get(vIndex)
                output[offset++] = uBuffer.get(uIndex)
            }
        }
        return output
    }

    private fun copyPlane(
        buffer: java.nio.ByteBuffer,
        rowStride: Int,
        pixelStride: Int,
        width: Int,
        height: Int,
        output: ByteArray,
        outputOffset: Int,
        outputPixelStride: Int
    ) {
        val src = buffer.duplicate()
        var out = outputOffset
        for (row in 0 until height) {
            val rowStart = row * rowStride
            for (col in 0 until width) {
                val index = rowStart + col * pixelStride
                if (index >= src.limit() || out >= output.size) return
                output[out] = src.get(index)
                out += outputPixelStride
            }
        }
    }

    private fun stopEverything() {
        try { virtualDisplay?.release() } catch (e: Exception) {}
        virtualDisplay = null
        try { imageReader?.close() } catch (e: Exception) {}
        imageReader = null
        try { cameraProvider?.unbindAll() } catch (e: Exception) {}
        cameraProvider = null
        try { mediaProjection?.unregisterCallback(projectionCallback) } catch (e: Exception) {}
        try { mediaProjection?.stop() } catch (e: Exception) {}
        mediaProjection = null
        try { handlerThread?.quitSafely() } catch (e: Exception) {}
        handlerThread = null
        backgroundHandler = null
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
    }

    override fun onDestroy() {
        stopEverything()
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        try { cameraExecutor.shutdown() } catch (e: Exception) {}
        try { networkExecutor.shutdownNow() } catch (e: Exception) {}
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun screenError(code: String, msg: String) {
        CaptureSinks.screenSink?.get()?.error(code, msg, null)
    }

    private fun metrics(): DisplayMetrics {
        val m = DisplayMetrics()
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(m)
        return m
    }

    private fun mainHandler() = Handler(mainLooper)

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "答辩直播录制", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "答辩直播屏幕录制与摄像头采集" }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val stopIntent = Intent(this, ScreenCaptureService::class.java).apply { action = ACTION_STOP }
        val stopPending = android.app.PendingIntent.getService(
            this, 0, stopIntent,
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return builder
            .setContentTitle("答辩直播进行中")
            .setContentText("正在录制屏幕与摄像头")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPending)
            .build()
    }
}
