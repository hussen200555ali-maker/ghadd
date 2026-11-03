package app.ghadd.guard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * [0.3.3] الإنقاذ الذاتي — الحل الجذري لسقوط جلسة الالتقاط على أندرويد 9/10.
 *
 * الجذر الحقيقي: توكن MediaProjection يعيش في الذاكرة فقط، وتُسقط الجلسة بنقرة
 * «إيقاف» في إشعار النظام أو بموت العملية (سامسونج يقتل الخلفية النائمة) —
 * سلوك نظامي لا يمكن منعه برمجيًا. القديم كان يعلم بالسقوط ثم يسكت: الحماية
 * تصبح عمياء بلا أي إشعار، والمستخدم لا يكتشف إلا بنفسه.
 *
 * الحل — طبقتان بترتيب تفضيل المستخدم (طلب المالك: «لا يوقفه النظام أبدًا
 * حتى يوقفه يدويًا»):
 *  1) الاسترداد الصفري (autoRecovery — مفعّل افتراضيًا): لحظة السقوط نُطلق
 *     [RestoreActivity] الشفاف فيفتح حوار النظام فوق ما كنت فيه مباشرة،
 *     وتنقر خدمة الوصول «البدء الآن» آليًا داخل نافذة مسلّحة 45 ثانية —
 *     الحماية تُستعاد بلا لمسة واحدة، ولا شيء يظهر سوى وميض حوار النظام.
 *  2) مسار الإشعار (الاسترداد التلقائي مطفأ بيدك): إشعار heads-up بنقرة واحدة
 *     يفتح التطبيق بعلم auto_projection فيُطلق الحوار فورًا.
 *
 * أمان التدفق: لا إطلاق أبدًا حين تكون الحماية مقفلة (canGuard)، ولا قبل
 * نافذة 60 ثانية (إشعار/حوار واحد لكل سقوط)، ولا خلال 10 دقائق بعد إلغائك
 * الحوار بيدك — نحن نستعيد الحماية، ونحن نصغك حين ترفض. ولا شيء من هذا
 * على أندرويد 11+ (المسار الأساسي بلا جلسات إطلاقًا).
 */
object RecoveryNotifier {
    const val CHANNEL_ID = "guard_recovery"
    const val EXTRA_AUTO_PROJECTION = "auto_projection"
    const val NOTIFICATION_ID = 1003
    private const val WINDOW_MS = 60_000L
    private const val CANCEL_COOLDOWN_MS = 10 * 60_000L
    private const val AUTO_CONSENT_WINDOW_MS = 45_000L

    private var lastAt = 0L
    private var userCancelledUntil = 0L

    /**
     * [0.3.3] نافذة النقر التلقائي المسلّحة: تُضبط لحظة إطلاق حوار الاستعادة
     * من [RestoreActivity] حصرًا (لا شيء آخر يسلّحها) — خدمة الوصول تنقر زر
     * «البدء الآن» فقط داخل هذه النافذة. التنصيت خارجها مستحيل بالتصميم.
     */
    @Volatile
    private var autoConsentUntil = 0L

    fun armAutoConsent() {
        autoConsentUntil = System.currentTimeMillis() + AUTO_CONSENT_WINDOW_MS
    }

    fun autoConsentFresh(): Boolean = System.currentTimeMillis() < autoConsentUntil

    fun disarmAutoConsent() {
        autoConsentUntil = 0L
    }

    /** ألغيتَ حوار الاستعادة بيدك — هدوء 10 دقائق قبل أي إطلاق تلقائي جديد. */
    fun noteUserCancelled() {
        userCancelledUntil = System.currentTimeMillis() + CANCEL_COOLDOWN_MS
        disarmAutoConsent()
        GuardLog.add("ألغيت حوار الاستعادة بيدك — الهدوء 10 دقائق (الاسترداد اليدوي من التطبيق متاح دائمًا)")
    }

    /**
     * إنقاذ سقوط الجلسة: الاسترداد الصفري أولًا (حوار يؤكَّد آليًا)، وإلا
     * إشعار heads-up بنقرة. يرد true إن بدأ مسار إنقاذ فعلًا (للتوثيق).
     */
    fun maybeNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 30) return false   // المسار الأساسي بلا جلسات
        if (!GuardPrefs.canGuard(context)) return false // الحماية مقفلة بيدك — لا استرداد
        val now = System.currentTimeMillis()
        if (now < userCancelledUntil) return false      // ألغيتَ بيدك — نصغك
        if (now - lastAt < WINDOW_MS) return false      // إنقاذ واحد لكل سقوط
        lastAt = now

        // الطبقة الأولى — الاسترداد الصفري: نشاط شفاف يفتح حوار النظام فوق
        // ما كنت فيه ويؤكَّد آليًا (خدمة الوصول تنقر «البدء الآن»). إن أُطلق
        // فلا إشعار — الحوار نفسه هو البليغ.
        if (GuardPrefs.autoRecovery(context)) {
            val launched = try {
                context.startActivity(
                    Intent(context, RestoreActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                true
            } catch (t: Throwable) {
                GuardLog.add("تعذر إطلاق الاسترداد الصفري (${t.message}) — نسقط لإشعار الإنقاذ")
                false
            }
            if (launched) {
                GuardLog.add("⚡ استرداد صفري: فُتح حوار الاستعادة فوق شاشتك الحالية — سيؤكَّد بلا لمسة منك")
                return true
            }
        }
        return postRecoveryNotification(context)
    }

    /** الطبقة الثانية — إشعار الإنقاذ بنقرة (مسار اليد حين الاسترداد التلقائي مطفأ). */
    private fun postRecoveryNotification(context: Context): Boolean {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.recovery_notification_title),
                NotificationManager.IMPORTANCE_HIGH
            ).apply { setShowBadge(false) }
        )
        val open = Intent(context, MainActivity::class.java)
            .putExtra(EXTRA_AUTO_PROJECTION, true)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(
            context, 778, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val text = context.getString(R.string.recovery_notification_text)
        val n: Notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle(context.getString(R.string.recovery_notification_title))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        nm.notify(NOTIFICATION_ID, n)
        GuardLog.add("⚠️ سقطت جلسة الالتقاط — أُرسل إشعار الإنقاذ (استعادة بنقرة واحدة)")
        return true
    }
}
