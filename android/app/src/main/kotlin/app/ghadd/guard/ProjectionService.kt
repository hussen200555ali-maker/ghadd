package app.ghadd.guard

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * خدمة أمامية مخصصة لمسار الالتقاط البديل (أندرويد 9/10 فقط).
 *
 * API 29 يشترط أن تكون الخدمة الأمامية بنوع mediaProjection قيد التشغيل
 * *قبل* استدعاء getMediaProjection — لذلك الترتيب دائمًا:
 *  1) المستخدم يمنح حوار تصريح العرض من MainActivity (حوار النظام نفسه).
 *  2) تُبدأ هذه الخدمة الأمامية بإشعار دائم ظاهر — صدق الحالة.
 *  3) يُنشأ محرك الالتقاط داخل onStartCommand بعد startForeground مباشرة.
 *
 * START_NOT_STICKY مقصودة: التصريح نفسه لا يبقى بعد موت العملية، فإعادة
 * تشغيل صامتة ستكون خدمة بلا تصريح — الأصل أن يعيد المستخدم التأكيد بيد one.
 */
class ProjectionService : Service() {

    companion object {
        const val CHANNEL_ID = "guard_projection"
        const val NOTIFICATION_ID = 1002

        @JvmStatic
        fun start(context: android.content.Context, resultCode: Int, data: Intent) {
            val i = Intent(context, ProjectionService::class.java)
                .putExtra("resultCode", resultCode)
                .putExtra("data", data)
            context.startForegroundService(i)
        }

        @JvmStatic
        fun stop(context: android.content.Context) {
            context.stopService(Intent(context, ProjectionService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val rc = intent?.getIntExtra("resultCode", Activity.RESULT_CANCELED)
            ?: return START_NOT_STICKY
        @Suppress("DEPRECATION")
        val data = intent.getParcelableExtra<Intent>("data") ?: return START_NOT_STICKY

        ensureChannel()
        val notification: Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_view)
                .setContentTitle(getString(R.string.guard_notification_title))
                .setContentText(getString(R.string.projection_notification_text))
                .setOngoing(true)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build()

        // نوع mediaProjection شرط نظامي على API 29+ — وعلى API 28 يكفي startForeground العادي
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this, NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        ProjectionCaptureEngine.start(applicationContext, rc, data)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        ProjectionCaptureEngine.stop()
        super.onDestroy()
    }

    private fun ensureChannel() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.guard_notification_title),
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
        )
    }
}
