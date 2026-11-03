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
 * الحل: كشف السقوط لحظته من ثلاث نقاط (callback الجلسة + مراقب خدمة الوصول
 * الذي يعمل تحديدًا حين يكون المستخدم خارج التطبيق + فتح التطبيق)، وإطلاق
 * إشعار heads-up بنقرة واحدة يفتح التطبيق بعلم auto_projection فيُطلق حوار
 * النظام فورًا — الاسترداد الكامل بنقرتين من أي مكان بدل مطاردة بطاقة.
 *
 * Dedup: نافذة 60 ثانية + شرط canGuard — إشعار واحد لكل سقوط، ولا إزعاج
 * حين تكون الحماية مقفلة بيد المستخدم أصلًا، ولا شيء على أندرويد 11+
 * (المسار الأساسي بلا جلسات إطلاقًا).
 */
object RecoveryNotifier {
    const val CHANNEL_ID = "guard_recovery"
    const val EXTRA_AUTO_PROJECTION = "auto_projection"
    const val NOTIFICATION_ID = 1003
    private const val WINDOW_MS = 60_000L
    private var lastAt = 0L

    /** إشعار استرداد بضغطة — يرد true إن أُرسل فعلًا (للتوثيق في السجل). */
    fun maybeNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 30) return false   // المسار الأساسي بلا جلسات
        if (!GuardPrefs.canGuard(context)) return false // الحماية مقفلة بيدك — لا استرداد
        val now = System.currentTimeMillis()
        if (now - lastAt < WINDOW_MS) return false      // إشعار واحد لكل سقوط
        lastAt = now

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
        GuardLog.add("⚠️ سقطت جلسة الالتقاط — أُرسل إشعار الاسترداد (استعادة بنقرتين من أي مكان)")
        return true
    }
}
