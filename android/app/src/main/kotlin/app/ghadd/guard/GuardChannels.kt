package app.ghadd.guard

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * تسجيل قناتي ghadd/control وghadd/system على أي محرك Flutter في التطبيق.
 *
 * [إصلاح 0.2.3 — السبب الجذري الثاني]: كانت القناتان تُسجَّلان عبر
 * MainActivity.configureFlutterEngine على محرك الواجهة فقط، بينما محرك الكشف
 * الأوسطي (guardMain الذي تُطلقه خدمة إمكانية الوصول عبر FlutterEngineGroup)
 * كان بلا أي معالج لقناتنا: GuardBrain.ensure() يفشل فيه بصمت
 * (MissingPluginException تُبتلع في native_bridge)، فلا يُسجَّل النموذج
 * المدمج في سجل الحزمة، وتسقط نداءات scanBytes على النموذج الافتراضي
 * (opennsfw2_coreml) الذي يحتاج تنزيلًا من الشبكة — مستحيلًا بلا INTERNET —
 * فيظهر «ML model not downloaded» رغم أن النموذج 88MB داخل الـAPK.
 *
 * الحل: معالجات واحدة مشتركة تُسجَّل على محرك الواجهة (بنشاط كامل) وعلى محرك
 * guardMain (بلا نشاط — الميزات الحوارية تردّ برسالة واضحة ولا تُستدعى من
 * هناك أصلًا). سجل ModelRegistry للحزمة أحادي في العملية، لذا تسجيل النموذج
 * من أي محرك يخدم الكل.
 */
object GuardChannels {
    const val CONTROL = "ghadd/control"
    const val SYSTEM = "ghadd/system"

    /** رمز طلب حوار تصريح عرض الشاشة (MediaProjection). */
    const val REQ_PROJECTION = 777

    fun register(context: Context, messenger: BinaryMessenger, activity: Activity?) {
        MethodChannel(messenger, CONTROL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sync" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    (args["consent"] as? Boolean)?.let { GuardPrefs.setConsent(context, it) }
                    GuardPrefs.setEnabled(context, args["enabled"] as? Boolean ?: false)
                    (args["threshold"] as? Double)?.let { GuardPrefs.setThreshold(context, it) }
                    (args["whitelist"] as? List<*>)?.let {
                        GuardPrefs.setWhitelist(context, it.filterNotNull().map(Any::toString).toSet())
                    }
                    (args["expanded"] as? Boolean)?.let { GuardPrefs.setExpanded(context, it) }
                    (args["regionMode"] as? Boolean)?.let { GuardPrefs.setRegionMode(context, it) }
                    result.success(true)
                }
                "stats" -> result.success(GuardPrefs.stats(context))
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, SYSTEM).setMethodCallHandler { call, result ->
            when (call.method) {
                "startGuard" -> {
                    GuardForegroundService.start(context)
                    result.success(true)
                }
                "stopGuard" -> {
                    GuardForegroundService.stop(context)
                    result.success(true)
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        // من سياق خدمة (بلا نشاط) يشترط النظام علم NEW_TASK
                        if (activity == null) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(true)
                }
                "openOverlaySettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${context.packageName}")
                    ).apply {
                        if (activity == null) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(true)
                }
                "startProjection" -> {
                    // أندرويد 9/10 فقط: فتح حوار تصريح العرض (حوار النظام نفسه).
                    // يتطلب نشاطًا — من المحرك الأوسطي يُرد بالحالة دون حوار.
                    if (Build.VERSION.SDK_INT >= 30) {
                        result.success(mapOf("legacy" to false, "active" to false))
                    } else if (activity == null) {
                        result.success(
                            mapOf("legacy" to true, "active" to ProjectionCaptureEngine.isReady)
                        )
                    } else {
                        try {
                            val mpm = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                                as MediaProjectionManager
                            activity.startActivityForResult(mpm.createScreenCaptureIntent(), REQ_PROJECTION)
                            result.success(mapOf("legacy" to true, "active" to ProjectionCaptureEngine.isReady))
                        } catch (t: Throwable) {
                            result.success(mapOf("legacy" to true, "active" to false))
                        }
                    }
                }
                "projectionStatus" -> result.success(
                    mapOf(
                        "legacy" to (Build.VERSION.SDK_INT < 30),
                        "active" to ProjectionCaptureEngine.isReady
                    )
                )
                "batteryStatus" -> result.success(
                    // [0.3.2] حالة مقاومة النوم: هل التطبيق مستثنى من تحسين
                    // البطارية وDoze؟ الحقيقة من النظام مباشرة لا من ذاكرة الواجهة.
                    // [0.3.3] manufacturer: لإظهار بطاقة سامسونج المخصصة على الأجهزة
                    // المعنية فقط (تجربة إدارة الطاقة العدائية تختلف بكل مصنع).
                    mapOf(
                        "exempt" to isBatteryExempt(context),
                        "sdk" to Build.VERSION.SDK_INT,
                        "manufacturer" to Build.MANUFACTURER
                    )
                )
                "requestBatteryExemption" -> {
                    // [0.3.2] مقاومة النوم: يفتح حوار النظام «السماح لغَضّ بالعمل
                    // دائمًا في الخلفية؟» — قرار المستخدم حصريًا، لا منح صامت.
                    // من محرك بلا نشاط (guardMain) نفتح قائمة الاستثناء مباشرة بعلم NEW_TASK.
                    if (isBatteryExempt(context)) {
                        result.success(mapOf("exempt" to true, "opened" to false))
                    } else {
                        val opened = try {
                            val intent = if (activity != null) {
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:${context.packageName}")
                                )
                            } else {
                                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            true
                        } catch (t: Throwable) {
                            // بعض الأغلفة المصنّعية ترفض النداء المباشر — نسقط لقائمة الاستثناء
                            try {
                                context.startActivity(
                                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                true
                            } catch (_: Throwable) { false }
                        }
                        result.success(mapOf("exempt" to false, "opened" to opened))
                    }
                }
                "openVendorBatterySettings" -> {
                    // [0.3.3] الجذر الثاني لنوم سامسونج: استثناء تحسين البطارية
                    // (مقاومة النوم 0.3.2) لا يغطي طبقة سامسونج الخاصة «وضع
                    // التطبيقات غير المستخدمة في وضع السكون» — وهذه هي التي
                    // تقتل العملية خارج التطبيق. نفتح شاشة إدارة طاقة التطبيقات
                    // لدى سامسونج مباشرة بمحاولات متدرجة (أسماء نشاطات سامسونج
                    // تختلف بين الإصدارات — كل محاولة بـtry/منفصلة)، والسقوط
                    // الآمن النهائي: صفحة معلومات التطبيق (زر البطارية فيها).
                    var how = "failed"
                    val candidates = listOf(
                        Intent("com.samsung.android.sm.ui.battery"),
                        Intent("com.samsung.android.sm.APP_POWER_MANAGEMENT")
                    )
                    for (c in candidates) {
                        if (how != "failed") break
                        try {
                            c.setPackage("com.samsung.android.sm")
                            if (activity == null) c.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(c)
                            how = "samsung_battery"
                        } catch (_: Throwable) { /* المرشح التالي */ }
                    }
                    if (how == "failed") {
                        try {
                            val appInfo = Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:${context.packageName}")
                            )
                            if (activity == null) appInfo.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(appInfo)
                            how = "app_info"
                        } catch (_: Throwable) { /* لا شيء يُفتح — نرد failed */ }
                    }
                    result.success(mapOf("opened" to (how != "failed"), "how" to how))
                }
                "permissionStatus" -> {
                    // الحالة الحقيقية من النظام — لا اعتماد على ذاكرة الواجهة:
                    // خدمة الوصول تُقرأ من الإعدادات الآمنة، والعرض فوق التطبيقات
                    // من canDrawOverlays. هكذا يظهر المفتاح جاهزًا فور المنح الفعلي.
                    val enabled = Settings.Secure.getString(
                        context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                    ) ?: ""
                    result.success(
                        mapOf(
                            "accessibility" to (
                                enabled.contains(context.packageName) &&
                                    enabled.contains("GuardAccessibilityService")
                                ),
                            "overlay" to Settings.canDrawOverlays(context),
                            "sdk" to Build.VERSION.SDK_INT
                        )
                    )
                }
                "prepareModel" -> {
                    // تجهيز النموذجين المدمجين (نسخ من الأصول إلى filesDir) — أساس مسار الكشف.
                    // يُستدعى من المحركين: الواجهة (شاشة التشخيص) وguardMain قبل أول فحص.
                    // [0.3.0] معهما نموذج المناطق (كاشف YOLO للمربعات).
                    val path = GuardModelStore.ensure(context)
                    val regionsPath = GuardModelStore.ensureRegions(context)
                    result.success(
                        mapOf(
                            "ok" to (path != null),
                            "path" to (path ?: ""),
                            "modelId" to GuardModelStore.MODEL_ID,
                            "regionsOk" to (regionsPath != null),
                            "regionsPath" to (regionsPath ?: ""),
                            "regionsModelId" to GuardModelStore.REGIONS_MODEL_ID
                        )
                    )
                }
                "guardLogs" -> result.success(GuardLog.all())
                "logFromDart" -> {
                    GuardLog.add(call.arguments?.toString() ?: "")
                    result.success(true)
                }
                "testCapture" -> {
                    // اختبار مباشر لمسار الالتقاط من شاشة التشخيص (محرك الواجهة حصرًا)
                    // [0.3.1] كل مسار فشل يعيد رسالة سبب عربية — كانت الحالة الصامتة
                    // تظهر للواجهة «فشل: false» بلا أي دليل (بلاغ مالك المشروع).
                    if (activity == null) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "note" to "اختبار الالتقاط متاح من واجهة التطبيق فقط"
                            )
                        )
                    } else if (Build.VERSION.SDK_INT >= 30) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "note" to "على أندرويد 11+ يكون الالتقاط عبر خدمة الوصول مباشرة — استخدم زر اختبار الكشف"
                            )
                        )
                    } else if (!ProjectionCaptureEngine.isReady) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "note" to "المحرك غير جاهز — جلسة تصريح العرض سقطت (تُسقط بموت العملية بحكم النظام). أعد تفعيلها من بطاقة «تفعيل تصريح عرض الشاشة» في الشاشة الرئيسية ثم كرر الاختبار"
                            )
                        )
                    } else {
                        val started = System.currentTimeMillis()
                        ProjectionCaptureEngine.capture { jpeg, reason ->
                            val payload = mapOf(
                                "ok" to (jpeg != null),
                                "bytes" to (jpeg?.size ?: 0),
                                "ms" to (System.currentTimeMillis() - started),
                                "note" to reason
                            )
                            activity.runOnUiThread { result.success(payload) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** [0.3.2] قراءة استثناء البطارية من PowerManager — مصدر الحقيقة الوحيد. */
    private fun isBatteryExempt(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }
}
