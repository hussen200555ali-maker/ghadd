package app.ghadd.guard

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
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
 *  - ghadd/system:  إطلاق شاشات منح الصلاحيات وبدء/إيقاف الخدمة الدائمة.
 */
class MainActivity : FlutterActivity() {

    private val settingsChannel = "ghadd/control"
    private val systemChannel = "ghadd/system"

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
                    else -> result.notImplemented()
                }
            }
    }
}
