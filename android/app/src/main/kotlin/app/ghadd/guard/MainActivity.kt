package app.ghadd.guard

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * واجهة Flutter الرئيسية. معالجات القناتين ghadd/control وghadd/system انتقلت
 * إلى [GuardChannels] ليُسجَّلان على محرك الواجهة هنا وعلى محرك الكشف الأوسطي
 * (guardMain) في GuardAccessibilityService.ensureEngine — القنوات على محرك
 * واحد فقط كانت سبب فشل تسجيل النموذج في مسار الكشف الخلفي (إصلاح 0.2.3).
 */
class MainActivity : FlutterActivity() {

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

        GuardChannels.register(this, flutterEngine.dartExecutor.binaryMessenger, this)

        // [0.3.3] استرداد تلقائي: فُتح التطبيق من إشعار الإنقاذ (أو بأي طلب
        // auto_projection) — حوار النظام يُطلق فورًا بلا مطاردة بطاقة.
        maybeAutoProjection(intent)
    }

    /** [0.3.3] استرداد بضغطة: إشعار الإنقاذ يفتحنا بعلم auto_projection. */
    private fun maybeAutoProjection(intent: Intent?) {
        if (Build.VERSION.SDK_INT >= 30) return
        if (intent?.getBooleanExtra(RecoveryNotifier.EXTRA_AUTO_PROJECTION, false) != true) return
        if (ProjectionCaptureEngine.isReady) return
        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            startActivityForResult(mpm.createScreenCaptureIntent(), GuardChannels.REQ_PROJECTION)
            GuardLog.add("استرداد تلقائي: فُتح حوار تصريح العرض من إشعار الإنقاذ")
        } catch (t: Throwable) {
            Log.w("Ghadd", "تعذر فتح حوار الاسترداد: ${t.message}")
        }
    }

    /** نتيجة حوار تصريح العرض: عند المنح تبدأ الخدمة الأمامية ثم محرك الالتقاط. */
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == GuardChannels.REQ_PROJECTION) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                ProjectionService.start(this, resultCode, data)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** [0.3.3] التطبيق مفتوح ومفرد (singleTop) — إشعار الإنقاذ يصل هنا. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybeAutoProjection(intent)
    }
}
