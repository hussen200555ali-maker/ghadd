package app.ghadd.guard

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * واجهة Flutter الرئيسية + قناتان:
 *  - ghadd/control: تزامن الإعدادات (وموافقة الإفصاح) مع المرآة الأصلية GuardPrefs.
 *  - ghadd/system:  إطلاق شاشات منح الصلاحيات وبدء/إيقاف الخدمة الدائمة،
 *                   وعلى أندرويد 9/10: حوار تصريح عرض الشاشة (مسار الالتقاط البديل).
 */
class MainActivity : FlutterActivity() {

    private val settingsChannel = "ghadd/control"
    private val systemChannel = "ghadd/system"

    /** رمز طلب حوار تصريح عرض الشاشة (MediaProjection). */
    private val reqProjection = 777

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // إشعار الحالة الدائم (أندرويد 13+) — يُطلب مبكرًا بشفافية
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42
            )
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sync" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        (args["consent"] as? Boolean)?.let { GuardPrefs.setConsent(this, it) }
                        GuardPrefs.setEnabled(this, args["enabled"] as? Boolean ?: false)
                        (args["threshold"] as? Double)?.let { GuardPrefs.setThreshold(this, it) }
                        (args["whitelist"] as? List<*>)?.let {
                            GuardPrefs.setWhitelist(this, it.filterNotNull().map(Any::toString).toSet())
                        }
                        (args["expanded"] as? Boolean)?.let { GuardPrefs.setExpanded(this, it) }
                        result.success(true)
                    }
                    "stats" -> result.success(GuardPrefs.stats(this))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startGuard" -> {
                        GuardForegroundService.start(this)
                        result.success(true)
                    }
                    "stopGuard" -> {
                        GuardForegroundService.stop(this)
                        result.success(true)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "openOverlaySettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.success(true)
                    }
                    "startProjection" -> {
                        // أندرويد 9/10 فقط: فتح حوار تصريح العرض (حوار النظام نفسه)
                        if (Build.VERSION.SDK_INT >= 30) {
                            result.success(mapOf("legacy" to false, "active" to false))
                        } else {
                            try {
                                val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                                    as MediaProjectionManager
                                startActivityForResult(mpm.createScreenCaptureIntent(), reqProjection)
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
                    "permissionStatus" -> {
                        // الحالة الحقيقية من النظام — لا اعتماد على ذاكرة الواجهة:
                        // خدمة الوصول تُقرأ من الإعدادات الآمنة، والعرض فوق التطبيقات
                        // من canDrawOverlays. هكذا يظهر المفتاح جاهزًا فور المنح الفعلي.
                        val enabled = Settings.Secure.getString(
                            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                        ) ?: ""
                        result.success(
                            mapOf(
                                "accessibility" to (
                                    enabled.contains(packageName) &&
                                        enabled.contains("GuardAccessibilityService")
                                    ),
                                "overlay" to Settings.canDrawOverlays(this),
                                "sdk" to Build.VERSION.SDK_INT
                            )
                        )
                    }
                    "prepareModel" -> {
                        // تجهيز النموذج المدمج (نسخ من الأصول إلى filesDir) — أساس مسار الكشف
                        val path = GuardModelStore.ensure(this)
                        result.success(
                            mapOf(
                                "ok" to (path != null),
                                "path" to (path ?: ""),
                                "modelId" to GuardModelStore.MODEL_ID
                            )
                        )
                    }
                    "guardLogs" -> result.success(GuardLog.all())
                    "logFromDart" -> {
                        GuardLog.add(call.arguments?.toString() ?: "")
                        result.success(true)
                    }
                    "testCapture" -> {
                        // اختبار مباشر لمسار الالتقاط من شاشة التشخيص
                        if (Build.VERSION.SDK_INT >= 30) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "note" to "على أندرويد 11+ يكون الالتقاط عبر خدمة الوصول مباشرة — استخدم زر اختبار الكشف"
                                )
                            )
                        } else {
                            val started = System.currentTimeMillis()
                            ProjectionCaptureEngine.capture { jpeg ->
                                val payload = mapOf(
                                    "ok" to (jpeg != null),
                                    "bytes" to (jpeg?.size ?: 0),
                                    "ms" to (System.currentTimeMillis() - started)
                                )
                                runOnUiThread { result.success(payload) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** نتيجة حوار تصريح العرض: عند المنح تبدأ الخدمة الأمامية ثم محرك الالتقاط. */
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == reqProjection) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                ProjectionService.start(this, resultCode, data)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
