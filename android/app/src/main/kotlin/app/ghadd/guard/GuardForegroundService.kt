package app.ghadd.guard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat

/**
 * الخدمة الأمامية الدائمة: إشعار دائم + START_STICKY (القسم 4.3 من الوثيقة).
 * النظام يعيد تشغيلها تلقائيًا إذا أوقفها تحت ضغط الذاكرة.
 */
class GuardForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "guard_status"
        const val NOTIFICATION_ID = 1001

        @JvmStatic
        fun start(context: android.content.Context) {
            context.startForegroundService(Intent(context, GuardForegroundService::class.java))
        }

        @JvmStatic
        fun stop(context: android.content.Context) {
            context.stopService(Intent(context, GuardForegroundService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.guard_notification_title),
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification: Notification =
            androidx.core.app.NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_view)
                .setContentTitle(getString(R.string.guard_notification_title))
                .setContentText(getString(R.string.guard_notification_text))
                .setOngoing(true)
                .setForegroundServiceBehavior(androidx.core.app.NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build()

        // نوع specialUse موثق في PROPERTY_SPECIAL_USE_FGS_SUBTYPE ضمن البيان
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this, NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY // إعادة التشغيل التلقائية عند القتل — جوهر وعد "الدوام"
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // [0.3.3] وعد «لا إيقاف أبدًا إلا بيدك»: مسح التطبيق من «الأخيرة» لا
        // يوقف خدمة الحالة الدائمة — تُكمل عملها، وأي موت لاحق للعملية يعيدها
        // START_STICKY تلقائيًا.
        GuardLog.add("أُزيل التطبيق من «الأخيرة» — إشعار الحالة يبقى والحماية تكمل")
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
