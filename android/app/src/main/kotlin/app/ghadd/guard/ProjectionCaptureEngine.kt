package app.ghadd.guard

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Point
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * مسار الالتقاط البديل لأجهزة Android 9/10 (API 28/29) — حيث لا تتوفر واجهة
 * takeScreenshot الرسمية لخدمة إمكانية الوصول (متاحة من API 30 فصاعدًا).
 *
 * الفلسفة نفسها بلا أي انحراف (وثيقة الردّ التقني، السؤال 3):
 *  - تصريح العرض منحٌ يمنحه النظام نفسه بحواره الصريح — لا يُخزَّن إطلاقًا،
 *    ويُطلب مجددًا بعد كل إقلاع (سلوك النظام في API 28/29)، ويتوقف بنقرة واحدة.
 *  - الإطارات تصل ImageReader في الذاكرة المتطايرة → JPEG في ByteArrayOutputStream
 *    → بايتات وحيدة تمر إلى محرك الكشف — لا ملف وسيط في أي مجلد، ولا مرجع يبقى.
 *  - الإطار يُغلق (image.close) والبكسلات تُحرَّر (bitmap.recycle) قبل التحليل.
 */
object ProjectionCaptureEngine {

    private const val TAG = "Ghadd"
    private const val CAPTURE_TIMEOUT_MS = 800L

    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private val convertExecutor = Executors.newSingleThreadExecutor()

    private val capturePending = AtomicBoolean(false)
    private var pendingResult: ((ByteArray?, String?) -> Unit)? = null
    private var timeoutRunnable: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** هل التصريح منح والمحرك يعمل الآن؟ (حالة جلسة فقط — لا تُخزَّن على القرص) */
    val isReady: Boolean
        get() = projection != null && display != null

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.i(TAG, "أوقف النظام/المستخدم تصريح العرض — تفريغ محرك الالتقاط البديل")
            release()
        }
    }

    private val readerListener = ImageReader.OnImageAvailableListener { r ->
        onImageAvailable(r)
    }

    private fun onImageAvailable(r: ImageReader) {
        val img = r.acquireLatestImage() ?: return
        if (!capturePending.compareAndSet(true, false)) {
            img.close() // إطار مرور — يُصرَّف فورًا حتى لا يمتلئ طابور ImageReader
            return
        }
        deliver(img)
    }

    /**
     * يُستدعى من ProjectionService بعد بدء الخدمة الأمامية — على API 29 يشترط
     * النظام أن تكون خدمة أمامية بنوع mediaProjection قيد التشغيل قبل هذه اللحظة.
     */
    fun start(appContext: Context, resultCode: Int, data: Intent): Boolean {
        release() // أي جلسة قديمة تُفرَّغ أولًا
        return try {
            val mpm = appContext.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
            val mp = mpm.getMediaProjection(resultCode, data) ?: return false
            projection = mp
            mp.registerCallback(projectionCallback, mainHandler)

            val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val size = Point().also { wm.defaultDisplay.getRealSize(it) }
            val dpi = appContext.resources.displayMetrics.densityDpi

            thread = HandlerThread("ghadd-projection").also { it.start() }
            handler = Handler(thread!!.looper)

            val r = ImageReader.newInstance(size.x, size.y, PixelFormat.RGBA_8888, 3)
            r.setOnImageAvailableListener(readerListener, handler)
            reader = r

            display = mp.createVirtualDisplay(
                "ghadd-guard", size.x, size.y, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                r.surface, null, handler
            )
            Log.i(TAG, "محرك الالتقاط البديل جاهز — ${size.x}x${size.y}")
            GuardLog.add("محرك الالتقاط البديل جاهز — ${size.x}x${size.y}")
            true
        } catch (t: Throwable) {
            Log.e(TAG, "تعذر بدء مسار MediaProjection: ${t.message}")
            GuardLog.add("✗ فشل بدء محرك الالتقاط: ${t.message}")
            release()
            false
        }
    }

    fun stop() = release()

    /**
     * طلب إطار واحد: يعيد JPEG bytes عبر onResult في الخيط الرئيسي،
     * أو (null، سبب عربي واضح) عند فشل/مهلة/عدم جاهزية المحرك — لا استثناءات أبدًا.
     * [0.3.1] السبب الصريح: كانت حالات الفشل تعيد null صامتًا فتظهر للواجهة
     * كـ«فشل: false» بلا أي دليل — الآن كل مسار فشل يسمّي نفسه.
     */
    fun capture(onResult: (ByteArray?, String?) -> Unit) {
        val r = reader
        if (!isReady || r == null) {
            onResult(null, "المحرك غير جاهز — جلسة تصريح العرض سقطت (تُسقط بموت العملية بحكم النظام). أعد تفعيلها من الشاشة الرئيسية بنقرة واحدة")
            return
        }
        if (!capturePending.compareAndSet(false, true)) {
            onResult(null, "التقط سابق قيد الجري — أعد المحاولة بعد لحظة")
            return
        }
        pendingResult = onResult
        val to = Runnable {
            if (capturePending.compareAndSet(true, false)) {
                pendingResult = null
                onResult(null, "انقضت مهلة ${CAPTURE_TIMEOUT_MS} مللي ثانية بلا إطار من VirtualDisplay — العرض المُعكس متوقف (هل التصريح أوقفه؟)")
            }
        }
        timeoutRunnable = to
        mainHandler.postDelayed(to, CAPTURE_TIMEOUT_MS)
        // الإصلاح الحاسم للشاشات الساكنة: الطلب كان ينتظر «إطارًا جديدًا» لا يأتي
        // أبدًا إن لم تتغير البكسلات (صورة مفتوحة بلا حركة)، بينما الإطار الذي
        // يُظهر المحتوى الحالي غالبًا في الطابور منذ لحظة الحدث. نجرفه فورًا
        // من خيط الـImageReader نفسه؛ وإن لم يوجد نُكمل بانتظار المستمع كالسابق.
        handler?.post {
            val img = try {
                reader?.acquireLatestImage()
            } catch (_: Throwable) {
                null
            } ?: return@post
            if (capturePending.compareAndSet(true, false)) {
                deliver(img)
            } else {
                img.close()
            }
        }
    }

    /** [0.3.1] استهلاك إطار مُقبوض: مهلة مُلغاة، تحويل في خيط خلفي، والنتيجة في الخيط الرئيسي.
     *  الفشل في التحويل يعلن سببه بدل null الصامت. */
    private fun deliver(img: Image, reason: String? = null) {
        cancelTimeout()
        val cb = pendingResult
        pendingResult = null
        convertExecutor.execute {
            val jpeg = toJpegInMemory(img)
            mainHandler.post {
                when {
                    jpeg != null -> cb?.invoke(jpeg, null)
                    reason != null -> cb?.invoke(null, reason)
                    else -> cb?.invoke(null, "فشل تحويل الإطار إلى JPEG في الذاكرة")
                }
            }
        }
    }

    private fun cancelTimeout() {
        timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        timeoutRunnable = null
    }

    private fun release() {
        cancelTimeout()
        capturePending.set(false)
        pendingResult = null
        try { display?.release() } catch (_: Throwable) {}
        try { reader?.close() } catch (_: Throwable) {}
        try { projection?.stop() } catch (_: Throwable) {}
        display = null
        reader = null
        projection = null
        thread?.quitSafely()
        thread = null
        handler = null
    }

    /** Image → JPEG bytes في الذاكرة فقط — نفس عقد دورة الحياة في خدمة الوصول. */
    private fun toJpegInMemory(image: Image): ByteArray? {
        var bmp: Bitmap? = null
        return try {
            val plane = image.planes[0]
            val rowStride = plane.rowStride
            val pixelStride = plane.pixelStride
            val w = image.width
            val h = image.height
            val buffer = plane.buffer
            bmp = if (rowStride == w * pixelStride) {
                val bm = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                bm.copyPixelsFromBuffer(buffer)
                bm
            } else {
                // صفوف مبطنة (padding) — تُنسخ صفًا صفًا إلى مخزن محكم قبل إنشاء Bitmap
                val packed = ByteBuffer.allocate(w * h * pixelStride)
                for (row in 0 until h) {
                    buffer.position(row * rowStride)
                    val slice = buffer.slice()
                    slice.limit(w * pixelStride)
                    packed.put(slice)
                }
                packed.rewind()
                val bm = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                bm.copyPixelsFromBuffer(packed)
                bm
            }
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 85, out) // في RAM فقط — كما في المسار الأساسي
            out.toByteArray()
        } catch (t: Throwable) {
            Log.w(TAG, "تعذر تحويل إطار العرض: ${t.message}")
            null
        } finally {
            try { image.close() } catch (_: Throwable) {}
            bmp?.recycle() // تحرير البكسلات حتى عند الاستثناء
        }
    }
}
