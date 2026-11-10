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

    /**
     * [0.4.0] كاشف NudeNet YOLOv8m ذي 18 فئة (AGPL-3.0، 51.9MB بصيغة TFLite).
     * الأرشيف ومصدر الأوزان وبصماته موثقة في MODEL_LICENSES.md؛ يُنسخ إلى
     * filesDir مثل المصنّف، بلا تنزيل أو اتصال شبكي وقت التشغيل.
     */
    private const val REGIONS_ASSET = "flutter_assets/assets/models/nsfw_regions.tflite"

    /** معرف النموذج المسجّل في الحزمة — تستهدفه نداءات scanBytes. */
    const val MODEL_ID = "ghadd_nsfw"

    /** [0.3.0] معرف كاشف المناطق المسجّل بنوع detector في الحزمة. */
    const val REGIONS_MODEL_ID = "ghadd_nsfw_regions"

    /** يعيد المسار المطلق بعد ضمان النسخة، أو null عند الفشل (يُسجَّل في GuardLog). */
    fun ensure(context: Context): String? {
        return try {
            val dir = File(context.filesDir, "ghadd_models")
            val out = copyAssetIfNeeded(context, ASSET, File(dir, "nsfw.tflite"), 1_000_000)
            out?.absolutePath
        } catch (t: Throwable) {
            GuardLog.add("فشل تجهيز النموذج: ${t.message}")
            null
        }
    }

    /** [0.3.0] تجهيز نموذج المناطق بنفس عقد النسخ والعزل. */
    fun ensureRegions(context: Context): String? {
        return try {
            val dir = File(context.filesDir, "ghadd_models")
            val out = copyAssetIfNeeded(context, REGIONS_ASSET, File(dir, "nsfw_regions.tflite"), 40_000_000)
            out?.absolutePath
        } catch (t: Throwable) {
            GuardLog.add("فشل تجهيز نموذج المناطق: ${t.message}")
            null
        }
    }

    /** نسخ الأصل إلى ملفات التطبيق مرة واحدة (مع حارس حجم أدنى ضد الأصول المقطوعة). */
    private fun copyAssetIfNeeded(context: Context, assetPath: String, out: File, minBytes: Long): File? {
        return try {
            if (!out.isFile || out.length() < minBytes) {
                out.parentFile?.mkdirs()
                context.assets.open(assetPath).use { input ->
                    val tmp = File(out.parentFile, out.name + ".tmp")
                    tmp.outputStream().use { output -> input.copyTo(output) }
                    if (!tmp.renameTo(out)) {
                        tmp.copyTo(out, overwrite = true)
                        tmp.delete()
                    }
                }
                GuardLog.add("نموذج مدمج جُهِّز: ${out.name} (${out.length() / 1_000_000}MB)")
            }
            out
        } catch (t: Throwable) {
            GuardLog.add("فشل نسخ ${out.name}: ${t.message}")
            null
        }
    }
}
