package app.ghadd.guard

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle

/**
 * [0.3.3] نشاط الاستعادة الشفاف — قلب «الاسترداد الصفري».
 *
 * يُطلق من RecoveryNotifier لحظة سقوط جلسة الالتقاط خارج التطبيق (فقط حين
 * الحماية مفعّلة والاسترداد التلقائي مفعّل بيدك): شفاف بلا واجهة، فما تراه
 * عينك سوى حوار النظام نفسه يفتح فوق التطبيق الذي كنت فيه — ثم تنقر خدمة
 * الوصول «البدء الآن» آليًا (نافذة مسلّحة 45 ثانية أُضيفت لحظة الإطلاق
 * هنا وحصرًا) فتُستعاد الحماية بلا لمسة واحدة، وينطفئ الحوار وحده.
 *
 * لا سلطة قرار هنا: هذا النقر إعادة تأكيد لنفس الموافقة التي منحتها بيدك
 * لحظة التفعيل (لا يُخزَّن توكن أصلًا بحكم النظام — قرار خصوصية موثق)،
 * وإلغاؤك الحوار يعني هدوءًا 10 دقائق لكل الإطلاقات التلقائية.
 */
class RestoreActivity : Activity() {

    companion object {
        /** رمز طلب حوار الاستعادة — مستقل عن REQ_PROJECTION (777) الخاص بالواجهة. */
        const val REQ_RESTORE = 779
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // بوابات صارمة: أندرويد 9/10 فقط (المسار الأساسي 11+ بلا جلسات)،
        // الحماية مفعّلة بيدك، والجلسة ساقطة فعلًا — وإلا ننصرف بصمت.
        if (Build.VERSION.SDK_INT >= 30 ||
            !GuardPrefs.canGuard(this) ||
            ProjectionCaptureEngine.isReady
        ) {
            finish()
            return
        }
        try {
            val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            RecoveryNotifier.armAutoConsent() // النقر التلقائي مسلّح الآن — حوارنا هو
            startActivityForResult(mpm.createScreenCaptureIntent(), REQ_RESTORE)
            GuardLog.add("استرداد صفري: حوار النظام يُفتح الآن فوق تطبيقك الحالي")
        } catch (t: Throwable) {
            RecoveryNotifier.disarmAutoConsent()
            GuardLog.add("تعذر فتح حوار الاستعادة: ${t.message}")
            finish()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_RESTORE) {
            finish()
            return
        }
        if (resultCode == RESULT_OK && data != null) {
            // المنح — تعاد الحماية فورًا: الخدمة الأمامية تنهض ومحرك الالتقاط
            // يُبنى داخلها كما في التفعيل الأول بالضبط.
            ProjectionService.start(applicationContext, resultCode, data)
            GuardLog.add("⚡ الجلسة استُعيدت بلا لمسة منك — الحماية تكمل حيث كانت")
        } else {
            // ألغيتَ بيدك — نصغك: لا إطلاقات تلقائية لمدة 10 دقائق
            // (RecoveryNotifier.noteUserCancelled يسجل الهدوء ويفكّ التسليح).
            RecoveryNotifier.noteUserCancelled()
        }
        finish()
    }
}
