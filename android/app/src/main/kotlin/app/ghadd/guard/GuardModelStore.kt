package app.ghadd.guard

import android.content.Context
import java.io.File

/**
 * متجر النموذج المدمج — إصلاح السبب الجذري لصمت الكشف:
 *
 * حزمة nsfw_detect لا تضمّن نماذجها داخل الـAPK بل تنزّلها من الشبكة عند أول
 * استخدام (كما يقرّ كودها الأصلي نفسه) — وهذا مستحيل في تطبيق بلا صلاحية
 * INTERNET، فكان scanBytes يفشل دائمًا بصمت ولا يعمل الطمس أبدًا.
 *
 * الحل: النموذج الحقيقي (Falconsai ViT-224 — 88MB) مدمج الآن داخل أصول الـAPK،
 * ويُنسخ هنا مرة واحدة إلى ملفات التطبيق الخاصة (filesDir) — المسار الوحيد
 * الذي تصادق عليه الحزمة عبر registerModel (تحقق داخل العزلة + وجود + بصمة TFL3).
 *
 * لا شبكة إطلاقًا — النموذج جزء من الـAPK منذ التثبيت.
 */
object GuardModelStore {
    private const val ASSET = "flutter_assets/assets/models/nsfw.tflite"

    /** معرف النموذج المسجّل في الحزمة — تستهدفه نداءات scanBytes. */
    const val MODEL_ID = "ghadd_nsfw"

    /** يعيد المسار المطلق بعد ضمان النسخة، أو null عند الفشل (يُسجَّل في GuardLog). */
    fun ensure(context: Context): String? {
        return try {
            val dir = File(context.filesDir, "ghadd_models")
            val out = File(dir, "nsfw.tflite")
            if (!out.isFile || out.length() < 1_000_000) {
                dir.mkdirs()
                context.assets.open(ASSET).use { input ->
                    val tmp = File(dir, "nsfw.tflite.tmp")
                    tmp.outputStream().use { output -> input.copyTo(output) }
                    if (!tmp.renameTo(out)) {
                        tmp.copyTo(out, overwrite = true)
                        tmp.delete()
                    }
                }
                GuardLog.add("النموذج المدمج جُهِّز في ملفات التطبيق (${out.length() / 1_000_000}MB)")
            } else {
                GuardLog.add("النموذج المدمج جاهز مسبقًا")
            }
            out.absolutePath
        } catch (t: Throwable) {
            GuardLog.add("فشل تجهيز النموذج: ${t.message}")
            null
        }
    }
}
