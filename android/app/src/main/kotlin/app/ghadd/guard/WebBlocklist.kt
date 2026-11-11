package app.ghadd.guard

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.net.IDN
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.Locale
import java.util.zip.GZIPInputStream

/**
 * [0.3.6] حجب المواقع المشبوهة — المطابقة محلية 100% بلا أي شبكة (لا INTERNET إطلاقًا).
 *
 * المصدر: قائمتان مضغوطتان داخل أصول الـAPK (assets/blocklists/*.gz)، كل واحدة نص
 * مرتّب بترتيب البايتات (LC_ALL=C) سطر لكل نطاق. عند أول استخدام تُفك إلى
 * filesDir مرة واحدة (إصدار بالاسم VERSION كي يُعاد البناء عند تحديث القوائم)،
 * ثم تُربط بالذاكرة (mmap) ويجري البحث الثنائي فوقها مباشرة — بلا أي فهرس في
 * الذاكرة وبلا تحميل 18MB إلى RAM (الصفحات تُجلب عند الطلب فقط، والبحث الثنائي
 * يلمس ~20 موقعًا صغيرًا لكل استعلام).
 *
 * التصنيفان:
 *  - "adult": نطاقات إباحية (~952 ألف نطاق — Block List Project: Porn).
 *  - "harm":  نطاقات احتيالية/خبيثة/تصيّد (~283 ألف نطاق — Fraud + Scam + Phishing Army).
 *
 * الخصوصية: لا يُخزَّن ولا يُسجَّل أي رابط أو نطاق يزوره المستخدم — الدالة تعيد
 * تصنيفًا فقط ولا تكتب شيئًا، والعدادات في GuardPrefs بلا أي نص.
 *
 * الاستدعاء من خيط خلفي حصرًا (urlExecutor في GuardAccessibilityService):
 * أول ensure() يفك الضغط (~2-4 ثوانٍ مرة واحدة) ثم كل categorize() ميكروثوانٍ.
 */
object WebBlocklist {

    private const val TAG = "Ghadd"
    /** ارفع هذا الاسم عند إعادة بناء القوائم كي تُفك نسخة جديدة إلى filesDir. */
    private const val VERSION = "2026a"
    private const val ASSET_ADULT = "blocklists/adult.txt.gz"
    private const val ASSET_HARM = "blocklists/harm.txt.gz"

    /** مخططات غير مواقع حقيقية — تُتجاهل قبل أي مطابقة (شريط العنوان يعرضها داخل المتصفحات). */
    private val NON_URL_PREFIXES = listOf(
        "about:", "chrome:", "content:", "file:", "intent:", "javascript:",
        "data:", "view-source:", "edge:", "brave:", "opera:", "internal:", "android-app:"
    )

    /** بنية نطاق صالحة (بعد تطبيع الحالة والأحرف). */
    private val DOMAIN_RE =
        Regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$")

    private val lock = Any()

    // @Volatile: القراءة خارج القفل في ensure()/categorize() — الرؤية بين الخيوط واجبة
    @Volatile
    private var adultBuf: ByteBuffer? = null
    @Volatile
    private var harmBuf: ByteBuffer? = null
    @Volatile
    private var ready = false
    @Volatile
    private var failed = false

    /** عدّادات للسجل التشخيصي فقط — بلا أي محتوى. */
    var adultDomains = 0
        private set
    var harmDomains = 0
        private set

    /** تهيئة القائمتين (فك الضغط أول مرة ثم الربط بالذاكرة). آمن للاستدعاء المتكرر. */
    fun ensure(context: Context): Boolean {
        if (ready) return true
        if (failed) return false
        synchronized(lock) {
            if (ready) return true
            if (failed) return false
            try {
                val started = System.currentTimeMillis()
                val a = mapGzAsset(context, ASSET_ADULT, "web_adult_$VERSION.bin")
                val h = mapGzAsset(context, ASSET_HARM, "web_harm_$VERSION.bin")
                adultDomains = a.second
                harmDomains = h.second
                adultBuf = a.first
                harmBuf = h.first
                ready = a.first != null && h.first != null
                if (!ready) {
                    failed = true
                    Log.e(TAG, "قوائم حجب المواقع غير متاحة")
                } else {
                    Log.i(
                        TAG,
                        "قوائم حجب المواقع جاهزة: $adultDomains إباحي + $harmDomains خبيث " +
                            "(${System.currentTimeMillis() - started}ms)"
                    )
                    GuardLog.add("🛡 قوائم حجب المواقع جاهزة محليًا ($adultDomains إباحي، $harmDomains خبيث)")
                }
            } catch (t: Throwable) {
                failed = true
                Log.e(TAG, "تعذر تجهيز قوائم الحجب: ${t.message}")
            }
            return ready
        }
    }

    /**
     * تصنيف نطاق مُطبَّع: "adult" / "harm" / null. يفحص النطاق نفسه ثم كل
     * نطاقات الأب كي يصيد sub.porn-site.com بنتيجة porn-site.com القياسية.
     */
    fun categorize(host: String): String? {
        if (!ready) return null
        val adult = adultBuf ?: return null
        val harm = harmBuf ?: return null
        val parts = host.split('.').filter { it.isNotEmpty() }
        if (parts.size < 2) return null
        // النطاق نفسه أولًا ثم الأب فالجد — الأقرب أولاً
        for (i in parts.indices) {
            val candidate = parts.subList(i, parts.size).joinToString(".")
            if (contains(adult, candidate)) return "adult"
            if (contains(harm, candidate)) return "harm"
        }
        return null
    }

    /** فحص سريع: هل يشبه النص عنوانًا وليس بحثًا أو نصًا حرًا أو مخططًا داخليًا؟ */
    fun looksLikeUrl(raw: String): Boolean {
        val s = raw.trim()
        if (s.isEmpty() || s.length > 300) return false
        if (s.contains(' ') || s.contains('\n') || s.contains('\t')) return false
        val lower = s.lowercase(Locale.US)
        for (p in NON_URL_PREFIXES) if (lower.startsWith(p)) return false
        return lower.contains('.')
    }

    /**
     * تطبيع نص شريط العنوان إلى نطاق جاهز للمطابقة، أو null إن لم يكن موقعًا:
     * إزالة المخطط والمسار والمنفذ ومعلومات المستخدم (خدعة user@host) وwww،
     * ورفض IPv6/الوايلدكارد/الترميز المئوي، وتحويل IDN إلى punycode.
     */
    fun normalizeHost(raw: String): String? {
        var s = raw.trim().lowercase(Locale.US)
        if (s.isEmpty() || s.length > 300 || s.contains(' ')) return null
        for (p in NON_URL_PREFIXES) if (s.startsWith(p)) return null
        s = s.removePrefix("https://").removePrefix("http://").removePrefix("ftp://")
        if (s.contains('[') || s.contains('*') || s.contains('%')) return null
        s = s.substringBefore('/')          // المسار
        s = s.substringAfterLast('@')       // خدعة user@host — النطاق بعد آخر @
        s = s.substringBefore(':')          // المنفذ
        while (s.startsWith("www.")) s = s.removePrefix("www.")
        if (s.length < 4 || s.endsWith('.') || s.startsWith('.')) return null
        if (!DOMAIN_RE.matches(s)) return null
        val ascii = try {
            IDN.toASCII(s, IDN.USE_STD3_ASCII_RULES).lowercase(Locale.US)
        } catch (t: Throwable) {
            s // نطاقات غير قياسية نادرة — البحث عن الشكل الخام، لن يطابق غالبًا وسنتجاهل بهدوء
        }
        return ascii
    }

    // ==================== البحث الثنائي فوق ملف مرتب ====================

    /**
     * بحث ثنائي على ملف نصي مرتّب بترتيب البايتات (sort LC_ALL=C):
     * ننتقل في كل خطوة إلى بداية السطر عند/بعد منتصف النطاق ونقارن البايتات
     * unsigned — مطابق تمامًا لترتيب الفرز. القراءة بـget(index) المطلق
     * فلا حالة داخلية تُعدَّل، والاستدعاء المتزامن آمن.
     */
    private fun contains(buf: ByteBuffer, target: String): Boolean {
        val t = target.toByteArray(Charsets.UTF_8)
        val cap = buf.capacity()
        var lo = 0
        var hi = cap
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            // بداية السطر الحاوي للمنتصف: آخر '\n' قبله ثم +1 (وإن لم يوجد فالبداية 0)
            var start = mid
            if (start > 0) {
                var p = start - 1
                while (p >= 0 && buf.get(p) != '\n'.code.toByte()) p--
                start = p + 1
            }
            var end = start
            while (end < cap && buf.get(end) != '\n'.code.toByte()) end++
            val len = end - start
            if (len <= 0) {
                lo = end + 1
                continue
            }
            // مقارنة بايت-ببايت بترتيب unsigned — مطابق لفرز LC_ALL=C
            var cmp = 0
            var i = 0
            while (i < len && i < t.size) {
                val a = buf.get(start + i).toInt() and 0xFF
                val b = t[i].toInt() and 0xFF
                if (a != b) {
                    cmp = if (a < b) -1 else 1
                    break
                }
                i++
            }
            // لم يوجد اختلاف: السطر الأطول أكبر (السطر بادئة الهدف = أصغر، والعكس)
            if (cmp == 0 && i == t.size && len > t.size) cmp = 1
            if (cmp == 0 && i == len && t.size > len) cmp = -1
            if (cmp == 0) return true
            if (cmp < 0) lo = end + 1 else hi = start
        }
        return false
    }

    /** فك أصل مضغوط إلى filesDir مرة واحدة (إصدار بالاسم) ثم ربطه بالذاكرة وعدّ أسطره. */
    private fun mapGzAsset(context: Context, asset: String, fileName: String): Pair<ByteBuffer, Int>? {
        val f = File(context.filesDir, fileName)
        if (!f.exists() || f.length() == 0L) {
            context.assets.open(asset).use { input ->
                GZIPInputStream(input, 1 shl 16).use { gz ->
                    FileOutputStream(f).use { out -> gz.copyTo(out, 1 shl 16) }
                }
            }
        }
        if (!f.exists() || f.length() == 0L) return null
        val ch = FileChannel.open(f.toPath(), FileChannel.MapMode.READ_ONLY)
        try {
            val buf = ch.map(FileChannel.MapMode.READ_ONLY, 0, f.length())
            var count = 0
            val cap = buf.capacity()
            var i = 0
            while (i < cap) {
                if (buf.get(i) == '\n'.code.toByte()) count++
                i++
            }
            return buf to count
        } finally {
            ch.close() // الخريطة تبقى صالحة بعد إغلاق القناة
        }
    }
}
