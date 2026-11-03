package app.ghadd.guard

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager

/**
 * طبقة الاستجابة — وضعان (القسم 4.1، الطبقة الثالثة):
 *
 * 1) show() — التغطية الكاملة للشاشة (سلوك 0.2.x): نافذة مانعة للمس تختفي
 *    بعد مهلة أو بنقرة المستخدم.
 *
 * 2) showRegions() — [0.3.0] تجربة المستخدم المثالية: نافذة واحدة
 *    FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE ترسم مستطيلات الطمس على المناطق
 *    المكتشفة فقط — اللمس يمر عبر كل شيء (المستطيلات والفراغ) فيواصل المستخدم
 *    التمرير والكتابة وعمله كالمعتاد، وينحجب عنه البصر فقط. المربعات تُستبدل
 *    بكل فحص جديد وتنقضي تلقائيًا (REGION_TTL_MS) إن توقف التحديث.
 *
 * الإحداثيات تصل مُطبَّعة [0..1] نسبةً إلى إطار اللقطة، فتُضرب في مقاس الشاشة
 * الحقيقي هنا (اللقطة تُلتقط بنفس أبعاد العرض عمليًا، والتحاشي بهامش تضخيم
 * النفخة INFLATE في مسار Dart).
 */
object OverlayController {

    private const val AUTO_HIDE_MS = 8000L

    /** [0.3.0] عمر أقصى لتغطية المناطق بلا تحديث (النافذة تغطي ولا تحجب العمل). */
    private const val REGION_TTL_MS = 20_000L

    private var current: View? = null
    private var regionWindow: View? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val regionHideRunnable = Runnable { regionWindow?.let { removeRegionView(it) } }

    fun show(context: Context) {
        mainHandler.post { showInternal(context.applicationContext) }
    }

    private fun showInternal(context: Context) {
        if (!Settings.canDrawOverlays(context)) return
        if (current != null) return

        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val view = LayoutInflater.from(context).inflate(R.layout.overlay_block, null)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        try {
            wm.addView(view, params)
            current = view
            view.setOnClickListener { hide(context) }
            mainHandler.postDelayed({ hide(context) }, AUTO_HIDE_MS)
        } catch (_: Throwable) {
        }
    }

    fun hide(context: Context) {
        mainHandler.post {
            val v = current ?: return@post
            try {
                (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                    .removeView(v)
            } catch (_: Throwable) {
            }
            current = null
        }
    }

    // ==================== [0.3.0] وضع المناطق ====================

    /**
     * عرض تغطية المناطق: rects مُطبَّعة [0..1] (x, y, w, h نسبةً للإطار).
     * نافذة واحدة غير قابلة للمس ترسم المستطيلات — لا سرقة تركيز ولا ابتلاع
     * لمسات إطلاقًا، فيبقى عمل المستخدم جاريًا كما هو.
     */
    fun showRegions(context: Context, rects: List<List<Double>>) {
        if (rects.isEmpty()) {
            hideRegions(context)
            return
        }
        mainHandler.post { showRegionsInternal(context.applicationContext, rects) }
    }

    private fun showRegionsInternal(context: Context, rects: List<List<Double>>) {
        if (!Settings.canDrawOverlays(context)) return
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        // إزالة النافذة السابقة أولًا — كل فحص غير لائق يستبدل المربعات بأحدثها.
        regionWindow?.let { removeRegionView(it) }

        val metrics = context.resources.displayMetrics
        val screenW = metrics.widthPixels.toFloat()
        val screenH = metrics.heightPixels.toFloat()
        val regions = rects.mapNotNull { r ->
            if (r.size < 4) return@mapNotNull null
            RectF(
                (r[0] * screenW).coerceAtLeast(0f),
                (r[1] * screenH).coerceAtLeast(0f),
                ((r[0] + r[2]) * screenW).coerceAtMost(screenW),
                ((r[1] + r[3]) * screenH).coerceAtMost(screenH)
            )
        }.filter { it.width() > 8f && it.height() > 8f }
        if (regions.isEmpty()) return

        val view = RegionCoverView(context, regions)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.START }
        try {
            wm.addView(view, params)
            regionWindow = view
            // انقضاء تلقائي: إن لم يأتِ فحص أحدث (سليم أو غيره) خلال المهلة.
            mainHandler.removeCallbacks(regionHideRunnable)
            mainHandler.postDelayed(regionHideRunnable, REGION_TTL_MS)
        } catch (_: Throwable) {
        }
    }

    /** إخفاء تغطية المناطق (فحص لاحق سليم / نافذة متغيرة / انقضاء المهلة). */
    fun hideRegions(context: Context) {
        mainHandler.post {
            mainHandler.removeCallbacks(regionHideRunnable)
            regionWindow?.let { removeRegionView(it) }
        }
    }

    private fun removeRegionView(v: View) {
        try {
            (v.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                .removeView(v)
        } catch (_: Throwable) {
        }
        if (regionWindow === v) regionWindow = null
    }

    /**
     * رسم مستطيلات الطمس: حجب داكن شبه معتم بزوايا مستديرة وحد رقيق بلون
     * العلامة — يُحجب البصر ويبقى بقية الشاشة ظاهرة تمامًا.
     */
    private class RegionCoverView(context: Context, private val regions: List<RectF>) :
        View(context) {

        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(235, 12, 16, 24)
            style = Paint.Style.FILL
        }
        private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(190, 38, 166, 189)
            style = Paint.Style.STROKE
            strokeWidth = resources.displayMetrics.density * 2f
        }
        private val radius = resources.displayMetrics.density * 14f

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            for (r in regions) {
                canvas.drawRoundRect(r, radius, radius, fill)
                canvas.drawRoundRect(r, radius, radius, stroke)
            }
        }
    }
}
