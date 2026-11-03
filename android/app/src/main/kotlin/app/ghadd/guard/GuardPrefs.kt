package app.ghadd.guard

import android.content.Context
import android.content.SharedPreferences

/**
 * مرآة إعدادات محلية بسيطة تقرأها الخدمات الأصلية بسرعة (بلا مرور بفلتر).
 * تزامنها طبقة Flutter عبر قناة ghadd/control.
 * بوابة الموافقة: الخدمة لا تعمل إطلاقًا قبل canGuard = موافقة الإفصاح + مفتاح الحماية.
 */
object GuardPrefs {
    private const val FILE = "guard_native"

    private fun sp(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun enabled(ctx: Context): Boolean = sp(ctx).getBoolean("enabled", false)

    fun setEnabled(ctx: Context, value: Boolean) =
        sp(ctx).edit().putBoolean("enabled", value).apply()

    /** موافقة الإفصاح البارز (Prominent Disclosure) — شرط وجودي قبل أي عمل للخدمة. */
    fun consent(ctx: Context): Boolean = sp(ctx).getBoolean("consent", false)

    fun setConsent(ctx: Context, value: Boolean) =
        sp(ctx).edit().putBoolean("consent", value).apply()

    /** شرط الحماية الكامل: موافقة صريحة + مفتاح تشغيل — لا عمل بلا الاثنين معًا. */
    fun canGuard(ctx: Context): Boolean = consent(ctx) && enabled(ctx)

    fun threshold(ctx: Context): Double =
        Double.fromBits(sp(ctx).getLong("threshold", 0.7.toRawBits()))

    fun setThreshold(ctx: Context, value: Double) =
        sp(ctx).edit().putLong("threshold", value.toRawBits()).apply()

    /**
     * التغطية الموسّعة (افتراضيًا مفعّلة بطلب المستخدم): تخفض حد الكشف الفعلي
     * ليمسك المحتوى غير المحتشم (أجساد/مكشوف) وليس الإباحي الصريح فقط.
     * النموذج ثنائي (آمن/غير آمن) — فالتوسعة تعني عتبة أقل (0.45) مع احتمال إزعاج أعلى.
     */
    fun expanded(ctx: Context): Boolean = sp(ctx).getBoolean("expanded", true)

    fun setExpanded(ctx: Context, value: Boolean) =
        sp(ctx).edit().putBoolean("expanded", value).apply()

    /**
     * [0.3.0] وضع المناطق (افتراضيًا مفعّل — تجربة المستخدم المثالية): عند الكشف
     * تُغطى المربعات المكتشفة فقط (بلا مانع لمس — العمل يواصل كالمعتاد)، مع
     * التغطية الكاملة للشاشة احتياطًا حين يتعذر تحديد مواضع.
     */
    fun regionMode(ctx: Context): Boolean = sp(ctx).getBoolean("region_mode", true)

    fun setRegionMode(ctx: Context, value: Boolean) =
        sp(ctx).edit().putBoolean("region_mode", value).apply()

    fun isWhitelisted(ctx: Context, packageName: String): Boolean =
        sp(ctx).getStringSet("whitelist", emptySet())?.contains(packageName) ?: false

    fun setWhitelist(ctx: Context, items: Set<String>) =
        sp(ctx).edit().putStringSet("whitelist", items).apply()

    // عدادات محلية فقط — لا شيء يغادر الجهاز (القسم 4.1، العداد المحلي)
    fun incrementBlocked(ctx: Context, packageName: String) {
        val p = sp(ctx)
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
            .format(java.util.Date())
        p.edit()
            .putInt("blocked_total", p.getInt("blocked_total", 0) + 1)
            .putInt("blocked_$today", p.getInt("blocked_$today", 0) + 1)
            .putString("last_blocked_at", java.lang.System.currentTimeMillis().toString())
            .putString("last_blocked_app", packageName)
            .apply()
    }

    fun stats(ctx: Context): Map<String, Any> {
        val p = sp(ctx)
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
            .format(java.util.Date())
        return mapOf(
            "blocked_total" to p.getInt("blocked_total", 0),
            "blocked_today" to p.getInt("blocked_$today", 0),
            "last_blocked_at" to (p.getString("last_blocked_at", null) ?: ""),
            "last_blocked_app" to (p.getString("last_blocked_app", null) ?: "")
        )
    }
}

private fun Double.toRawBits(): Long = java.lang.Double.doubleToRawLongBits(this)
private fun Long.toRawBits(): Long = this
