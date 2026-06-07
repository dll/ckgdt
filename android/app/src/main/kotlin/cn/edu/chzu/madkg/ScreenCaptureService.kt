package cn.edu.chzu.madkg

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
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
        private const val CHANNEL_ID = "defense_capture"
        private const val NOTIFICATION_ID = 0x5AD
    }

    private val lifecycleRegistry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = lifecycleRegistry

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var handlerThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private var cameraProvider: ProcessCameraProvider? = null
    private val cameraExecutor = Executors.newSingleThreadExecutor()

    // 复用缓冲，避免每帧分配
    private var screenNv21: ByteArray? = null
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

        var reader: ImageReader? = try {
            ImageReader.newInstance(width, height, ImageFormat.JPEG, 4)
        } catch (e: Exception) { null }
        if (reader == null) {
            reader = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 4)
        }
        imageReader = reader
        val isJpeg = reader.imageFormat == ImageFormat.JPEG

        reader.setOnImageAvailableListener({ r ->
            val image: Image = try { r.acquireLatestImage() } catch (e: Exception) { null } ?: return@setOnImageAvailableListener
            try {
                val bytes = if (isJpeg) {
                    val buf = image.planes[0].buffer
                    val b = ByteArray(buf.remaining()); buf.get(b); b
                } else {
                    yuvToJpeg(image, ::screenBufFor, screenJpeg)
                }
                if (bytes != null) CaptureSinks.screenSink?.get()?.success(bytes)
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
            val image = proxy.image
            if (image != null) {
                val bytes = yuvToJpeg(image, ::cameraBufFor, cameraJpeg)
                if (bytes != null) CaptureSinks.cameraSink?.get()?.success(bytes)
            }
        } catch (e: Exception) {
            // 忽略单帧
        } finally {
            proxy.close()
        }
    }

    // ── YUV_420_888 → NV21 → JPEG（复用缓冲） ─────────────────────────
    private fun screenBufFor(size: Int): ByteArray {
        var b = screenNv21
        if (b == null || b.size != size) { b = ByteArray(size); screenNv21 = b }
        return b
    }

    private fun cameraBufFor(size: Int): ByteArray {
        var b = cameraNv21
        if (b == null || b.size != size) { b = ByteArray(size); cameraNv21 = b }
        return b
    }

    private fun yuvToJpeg(image: Image, bufFor: (Int) -> ByteArray, out: ByteArrayOutputStream): ByteArray? {
        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer
        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()
        val nv21 = bufFor(ySize + uSize + vSize)
        yBuffer.get(nv21, 0, ySize)
        // NV21: VU 交错
        var pos = ySize
        val count = minOf(vSize, uSize)
        for (i in 0 until count) {
            nv21[pos++] = vBuffer.get()
            nv21[pos++] = uBuffer.get()
        }
        val yuv = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
        out.reset()
        yuv.compressToJpeg(Rect(0, 0, image.width, image.height), 70, out)
        return out.toByteArray()
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
