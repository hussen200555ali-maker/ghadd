package app.ghadd.guard

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.hardware.HardwareBuffer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * الطبقة الأولى (الالتقاط والاستيقاظ) + الجسر إلى محرك الكشف (القسم 4.1 من الوثيقة).
 *
 * عقد دورة حياة اللقطة (وثيقة الردّ التقني، السؤال 3 — «اللقطة لا تلمس القرص أصلًا»):
 *  1) takeScreenshot() → ScreenshotResult يحمل HardwareBuffer في الذاكرة المتطايرة فقط.
 *  2) نسخة Bitmap واحدة عبر wrapHardwareBuffer ثم copy — ثم hardwareBuffer.close() فورًا.
 *  3) ضغط JPEG جودة 85 داخل ByteArrayOutputStream — بلا أي ملف وسيط ولا مجلد cache.
 *  4) bitmap.recycle() مباشرة بعد الضغط — البكسلات تعود للنظام قبل بدء التحليل.
 *  5) ByteArray الوحيد يمر عبر قناة ghadd/analyze إلى محرك nsfw_detect (scanBytes).
 *  6) النتيجة تعود في reply الاستدعاء نفسها، ويحرسها عدّاد توليد + مهلة 5 ثوانٍ:
 *     أي نتيجة متأخرة أو قديمة تُهمل ولا تُطبَّق على إطار جديد.
 *  7) لا مرجع عام ولا سجلّ محتوى — عدّادات أرقام مجردة فقط في GuardPrefs.
 */
class GuardAccessibilityService : AccessibilityService() {

    companion object {
        const val TAG = "Ghadd"
        const val CHANNEL = "ghadd/analyze"
        const val DEBOUNCE_MS = 400L
        const val WATCHDOG_MS = 5_000L

        @Volatile
        var instance: GuardAccessibilityService? = null
            private set
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val screenshotExecutor = Executors.newSingleThreadExecutor()
    private var engine: FlutterEngine? = null
    private var pending = false
    private var lastHandledAt = 0L
    private var lastPackage: String? = null

    /** عدّاد التوليد: كل حدث جديد يُبطل أي نتيجة قديمة في الطريق (منع «الغلطة الزمنية»). */
    private var generation = 0
    private var deadlineGen = 0
    private var deadlineAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        GuardLog.add("خدمة إمكانية الوصول متصلة — جاهزة للالتقاط")
        Log.i(TAG, "خدمة إمكانية الوصول متصلة — حماية غَضّ جاهزة")
    }

    override fun onDestroy() {
        instance = null
        GuardLog.add("خدمة إمكانية الوصول انقطعت")
        super.onDestroy()
    }

    override fun onInterrupt() { /* لا شيء مطلوب */ }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !GuardPrefs.canGuard(this)) return
        val type = event.eventType
        if (type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        ) return

        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return                  // تجاهل نفسه
        if (GuardPrefs.isWhitelisted(this, pkg)) return // القائمة البيضاء (4.1)
        lastPackage = pkg

        val now = System.currentTimeMillis()
        if (now - lastHandledAt < DEBOUNCE_MS) {
            if (!pending) {
                pending = true
                mainHandler.postDelayed({
                    pending = false
                    captureAndAnalyze()
                }, DEBOUNCE_MS)
            }
            return
        }
        lastHandledAt = now
        captureAndAnalyze()
    }

    private fun captureAndAnalyze() {
        val svc = instance ?: return
        if (!GuardPrefs.canGuard(this)) return

        val g = ++generation
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // المسار الأساسي (أندرويد 11+): takeScreenshot الرسمي لخدمة إمكانية الوصول.
            // تطبيقات FLAG_SECURE ترفض الالتقاط هنا ببساطة (خطأ/فراغ) — لا يُنشأ كائن أصلًا
            // ولا يُزاد أي عدّاد محجوب؛ سلوك «الاحترام الفوري» في السؤال 4 من وثيقة الردّ.
            // التوقيع الرسمي (compileSdk 34): takeScreenshot(displayId, executor, callback)
            // والواجهة TakeScreenshotCallback بلا مُنشئ: onSuccess(ScreenshotResult) / onFailure(Int).
            svc.takeScreenshot(
                Display.DEFAULT_DISPLAY,
                screenshotExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(result: ScreenshotResult) {
                        if (g != generation) return // نتيجة متخلفة — تُهمل
                        val jpeg = toJpegInMemory(result.hardwareBuffer, result.colorSpace)
                        if (jpeg == null || g != generation) return
                        mainHandler.post { askDart(jpeg, g) }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.w(TAG, "فشل الالتقاط — رمز $errorCode (تطبيقات FLAG_SECURE ترفض ببساطة)")
                    }
                }
            )
        } else {
            // المسار البديل (أندرويد 9/10): محرك MediaProjection — نفس عقد دورة الحياة
            // (RAM فقط، بلا ملف وسيط) ونفس حراسة التوليد والمهلة، ونتائجه تمر إلى askDart مباشرة.
            // إن لم يمنح المستخدم تصريح العرض بعد فالمحرك غير جاهز → null → لا شيء يحدث.
            ProjectionCaptureEngine.capture { jpeg ->
                if (jpeg == null || g != generation) return@capture
                askDart(jpeg, g)
            }
        }
    }

    /** HardwareBuffer → JPEG bytes في الذاكرة فقط، مع إغلاق المصدر وتحرير البكسلات فورًا. */
    private fun toJpegInMemory(buffer: HardwareBuffer, cs: ColorSpace?): ByteArray? {
        var bmp: Bitmap? = null
        return try {
            val hw = Bitmap.wrapHardwareBuffer(buffer, cs) ?: return null
            bmp = hw.copy(Bitmap.Config.ARGB_8888, false)
            buffer.close() // أغلق المصدر بعد النسخ مباشرة — لا مرجعان للإطار أبدًا
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 85, out) // ~300KB — في RAM فقط
            out.toByteArray()
        } catch (t: Throwable) {
            Log.w(TAG, "تعذر تحويل اللقطة: ${t.message}")
            null
        } finally {
            bmp?.recycle() // تحرير البكسلات حتى عند الاستثناء (try/finally — السؤال 3)
        }
    }

    /** الجسر إلى محرك nsfw_detect الذي يعمل داخل isolate خلفي مخصص (guardMain). */
    private fun askDart(jpeg: ByteArray, g: Int) {
        val eng = ensureEngine() ?: return
        if (g != generation) return
        val pkg = lastPackage ?: "unknown"
        deadlineGen = g
        deadlineAt = System.currentTimeMillis() + WATCHDOG_MS

        MethodChannel(eng.dartExecutor.binaryMessenger, CHANNEL)
            .invokeMethod(
                "analyze",
                mapOf(
                    "bytes" to jpeg,
                    "threshold" to GuardPrefs.threshold(this),
                    "expanded" to GuardPrefs.expanded(this),
                    "pkg" to pkg
                ),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (!isFresh(g)) {
                            Log.i(TAG, "نتيجة متأخرة تُهمل — عدّاد التوليد/المهلة (السؤال 3)")
                            return
                        }
                        val map = result as? Map<*, *>
                        val unsafe = map?.get("unsafe") as? Boolean ?: false
                        val score = map?.get("score")
                        if (unsafe) {
                            GuardPrefs.incrementBlocked(this@GuardAccessibilityService, pkg)
                            // [0.3.0] وضع المناطق: مربعات مكتشفة → تغطيتها فقط (بلا مانع
                            // لمس — العمل يواصل). تعذر تحديد المواضع أو الوضع مطفأً →
                            // التغطية الكاملة كما في 0.2.x.
                            val regions = map?.get("regions") as? List<*>
                            val parsed = regions?.mapNotNull { r ->
                                (r as? List<*>)?.mapNotNull { (it as? Number)?.toDouble() }
                            }.orEmpty()
                            if (GuardPrefs.regionMode(this@GuardAccessibilityService) && parsed.isNotEmpty()) {
                                GuardLog.add("⚠ كشف غير لائق في $pkg — الدرجة $score — تغطية ${parsed.size} منطقة (العمل يواصل)")
                                OverlayController.showRegions(this@GuardAccessibilityService, parsed)
                            } else {
                                GuardLog.add("⚠ كشف محتوى غير لائق في $pkg — الدرجة $score — عرض الطمس الكامل")
                                OverlayController.show(this@GuardAccessibilityService)
                            }
                        } else {
                            GuardLog.add("فحص $pkg — آمن (أعلى درجة $score)")
                            // [0.3.0] فحص سليم لاحق → رفع أي تغطية مناطق عالقة فورًا.
                            OverlayController.hideRegions(this@GuardAccessibilityService)
                        }
                    }

                    override fun error(code: String, msg: String?, details: Any?) {
                        Log.w(TAG, "خطأ كشف: $code / $msg")
                        GuardLog.add("✗ خطأ كشف في $pkg: $code / $msg")
                    }

                    override fun notImplemented() {
                        Log.w(TAG, "قناة الكشف غير مهيأة بعد")
                        GuardLog.add("✗ قناة الكشف غير مهيأة بعد — محرك guardMain لم يبدأ")
                    }
                }
            )
    }

    /** هل ما تزال نتيجة هذا التوليد صالحة؟ (لم يحصل حدث أحدث ولم تُعد مهلة 5 ثوانٍ) */
    private fun isFresh(g: Int): Boolean =
        g == deadlineGen && System.currentTimeMillis() <= deadlineAt

    private fun ensureEngine(): FlutterEngine? {
        engine?.let { return it }
        return try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val entrypoint = DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "guardMain")
            val eng = FlutterEngineGroup(applicationContext)
                .createAndRunEngine(applicationContext, entrypoint)
            // [إصلاح 0.2.3 — جذري] المحرك الأوسطي بلا معالجات القنوات كان يُفشل
            // GuardBrain.ensure() بصمت (MissingPluginException) فلا يُسجَّل النموذج
            // المدمج وتنهار كل الفحوص على «النموذج الافتراضي يحتاج تنزيلًا».
            // الآن تُسجَّل القناتان المشتركتان هنا أيضًا — بلا نشاط (بلا حوارات).
            GuardChannels.register(applicationContext, eng.dartExecutor.binaryMessenger, null)
            engine = eng
            eng
        } catch (t: Throwable) {
            Log.e(TAG, "تعذر تشغيل محرك الكشف: ${t.message}")
            null
        }
    }
}
