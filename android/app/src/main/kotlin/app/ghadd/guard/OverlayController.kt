package app.ghadd.guard

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * طبقة الاستجابة — وضعان (القسم 4.1، الطبقة الثالثة):
 *
 * 1) show() — تغطية كاملة للشاشة عند تعذر التحقق أو عند عدم تحديد الموضع.
 *    لا تنقضي تلقائيًا؛ اللمس يمر إلى التطبيق أسفلها كي يستطيع المستخدم
 *    التنقل، ولا تُزال إلا بعد فحص آمن أو إيقاف الحماية يدويًا.
 *
 * 2) showRegions() — [0.3.0] تجربة المستخدم المثالية: نافذة واحدة
 *    FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE ترسم مستطيلات الطمس على المناطق
 *    المكتشفة فقط — اللمس يمر عبر كل شيء (المستطيلات والفراغ) فيواصل المستخدم
 *    التمرير والكتابة وعمله كالمعتاد، وينحجب عنه البصر فقط. المربعات تُستبدل
 *    بكل فحص جديد وتبقى ظاهرة إلى أن يأتي فحص آمن أو إيقاف يدوي.
 *
 * الإحداثيات تصل مُطبَّعة [0..1] نسبةً إلى إطار اللقطة، فتُضرب في مقاس الشاشة
 * الحقيقي هنا (اللقطة تُلتقط بنفس أبعاد العرض عمليًا، والتحاشي بهامش تضخيم
 * النفخة INFLATE في مسار Dart).
 */
object OverlayController {

    private var current: View? = null
    private var regionWindow: View? = null
    private var siteWindow: View? = null
    private var siteAutoHide: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun show(context: Context) {
        mainHandler.post { showInternal(context.applicationContext) }
    }

    private fun showInternal(context: Context) {
        if (!Settings.canDrawOverlays(context)) return
        if (current != null) return

        regionWindow?.let { removeRegionView(it) }

        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val view = LayoutInflater.from(context).inflate(R.layout.overlay_block, null)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        try {
            wm.addView(view, params)
            current = view
        } catch (_: Throwable) {
        }
    }

    fun hide(context: Context) {
        mainHandler.post {
            current?.let { removeCurrentView(context, it) }
        }
    }

    /**
     * إزالة كل الأقنعة البصرية بعد نتيجة آمنة أو عند إيقاف الحماية يدويًا.
     * شاشة حجب المواقع **ليست أقنعة بصرية**: الفحص الآمن الدوري يستدعي hideAll
     * بعد الخروج الآلي من الصفحة المحجوبة مباشرة — لو أزال شاشة الحجب لتلاشت
     * بعد لحظة. عمرها مستقل (زر «رجوع بأمان» أو 7 ثوانٍ)، وإيقاف الحماية يدويًا
     * (stopGuard) هو من يستدعيها بـincludeSite = true.
     */
    fun hideAll(context: Context, includeSite: Boolean = false) {
        mainHandler.post {
            current?.let { removeCurrentView(context, it) }
            regionWindow?.let { removeRegionView(it) }
            if (includeSite) {
                siteWindow?.let { removeSiteView(it) }
                cancelSiteAutoHide()
            }
        }
    }

    private fun removeCurrentView(context: Context, view: View) {
        try {
            (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(view)
        } catch (_: Throwable) {
        }
        if (current === view) current = null
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
        val screenW = metrics.widthPixels.toDouble()
        val screenH = metrics.heightPixels.toDouble()
        val regions = rects.mapNotNull { r ->
            if (r.size < 4) return@mapNotNull null
            val l = (r[0] * screenW).coerceAtLeast(0.0)
            val t = (r[1] * screenH).coerceAtLeast(0.0)
            val rt = ((r[0] + r[2]) * screenW).coerceAtMost(screenW)
            val b = ((r[1] + r[3]) * screenH).coerceAtMost(screenH)
            RectF(l.toFloat(), t.toFloat(), rt.toFloat(), b.toFloat())
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
            // إذا تعذر إنشاء قناع المناطق يبقى الغطاء الكامل السابق قائمًا؛
            // بعد نجاح الإضافة فقط يمكن استبداله بالقناع الأضيق.
            current?.let { removeCurrentView(context, it) }
        } catch (_: Throwable) {
        }
    }

    /** إخفاء تغطية المناطق بعد فحص آمن أو عند إيقاف الحماية يدويًا. */
    fun hideRegions(context: Context) {
        mainHandler.post {
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

    // ==================== [0.3.6] شاشة حجب المواقع ====================

    /**
     * شاشة حجب موقع مشبوه: تغطية كاملة قابلة للمس (زر «رجوع بأمان» يعمل)،
     * تُعرض بعد الخروج الآلي من الصفحة عبر GLOBAL_ACTION_HOME من خدمة إمكانية
     * الوصول. تُخفى بالزر أو آليًا بعد 7 ثوانٍ — لا تبقى عائقًا دائمًا.
     * هنا فقط تستخدم نافذة قابلة لللمس: التغطية تقتل الصفحة المحجوبة أساسًا
     * فلا لمسٌ يمرّ منها، والمستخدم يحتاج زر الخروج.
     */
    fun showSiteBlock(context: Context, category: String) {
        mainHandler.post { showSiteBlockInternal(context.applicationContext, category) }
    }

    private fun showSiteBlockInternal(context: Context, category: String) {
        if (!Settings.canDrawOverlays(context)) return
        siteWindow?.let { removeSiteView(it) }
        cancelSiteAutoHide()

        val d = context.resources.displayMetrics.density
        val dp = { v: Float -> (v * d).toInt() }

        fun label(text: String, sizeSp: Float, color: String, bold: Boolean, topDp: Int): TextView =
            TextView(context).apply {
                this.text = text
                textSize = sizeSp
                setTextColor(Color.parseColor(color))
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
                if (bold) setTypeface(typeface, Typeface.BOLD)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(topDp.toFloat()) }
            }

        val reason = if (category == "adult")
            "موقع مصنَّف إباحيًا — حجب محلي حسب إعدادات غَضّ"
        else
            "موقع مصنَّف احتياليًا أو خبيثًا — حجب محلي حسب إعدادات غَضّ"

        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(250, 8, 12, 20))
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(28f), dp(28f), dp(28f), dp(28f))
            addView(label("⛔", 46f, "#E8F0F8", bold = false, topDp = 0))
            addView(label("حُجب موقع مشبوه", 22f, "#E8F0F8", bold = true, topDp = 12))
            addView(label(reason, 14f, "#9FB6CC", bold = false, topDp = 10))
            addView(label(
                "المطابقة تمت على جهازك من قائمة مدمجة — لا يُسجَّل أي رابط تزوره",
                12f, "#6E86A0", bold = false, topDp = 6
            ))
        }

        val btn = Button(context).apply {
            text = "رجوع بأمان"
            textSize = 15f
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(22f) }
            setOnClickListener { hideSiteBlock(context) }
        }
        root.addView(btn)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        try {
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.addView(root, params)
            siteWindow = root
            // إخفاء آلي احتياطي — لا نترك شاشة حجب عالقة إذا خرج المستخدم بغير الزر
            siteAutoHide = Runnable { removeSiteView(root) }
            mainHandler.postDelayed(siteAutoHide, 7_000L)
        } catch (_: Throwable) {
        }
    }

    fun hideSiteBlock(context: Context) {
        mainHandler.post {
            siteWindow?.let { removeSiteView(it) }
            cancelSiteAutoHide()
        }
    }

    private fun removeSiteView(v: View) {
        try {
            (v.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                .removeView(v)
        } catch (_: Throwable) {
        }
        if (siteWindow === v) siteWindow = null
    }

    private fun cancelSiteAutoHide() {
        siteAutoHide?.let { mainHandler.removeCallbacks(it) }
        siteAutoHide = null
    }
}
