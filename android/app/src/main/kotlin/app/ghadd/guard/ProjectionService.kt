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
 * [0.3.3] سياسة «لا إيقاف أبدًا إلا بيدك»: الخدمة START_STICKY — إن قتل
 * النظام/المصنع العملية تعيد تشغيلها تلقائيًا، ومحاولة إعادة التشغيل الصامتة
 * (intent = null) لم تعد خدمة ميتة بلا تصريح كما في 0.3.1/0.3.2 بل لحظة إنقاذ:
 * canGuard واضح → RecoveryNotifier يُطلق الاسترداد الصفري (حوار يؤكّد آليًا)
 * أو إشعار الإنقاذ بنقرة — فلا تبقى الحماية عمياء أبدًا. ومسح التطبيق من
 * «الأخيرة» لا يوقف الخدمة (onTaskRemoved يواصل العمل ويسجل ذلك).
 *
 * [0.3.4] إصلاح جذري لحلقة «غَضّ توقف عن العمل» (Keeps stopping):
 * عقد startForegroundService لا يُعفى بإعادة التشغيل — حين يقتل المصنع
 * العملية ويعيد النظام الخدمة بـintent = null تبقى الخدمة ملزمة باستدعاء
 * startForeground خلال 5 ثوانٍ (علم fgRequired يبقى في سجل النظام)، وإلا
 * RemoteServiceException → رسالة الانهيار → موت العملية → سقوط خدمة الوصول
 * معها → الاسترداد يعيد الجلسة → القتل مجددًا → الحلقة المتكررة. الإصلاح:
 * استدعاء startForeground أولًا في كل المسارات بلا استثناء (حتى إعادة
 * التشغيل بلا توكن)، ثم نقرر المصير — إنقاذ بجلسة حية أو توقف هادئ بلا انهيار.
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
        // [0.3.4] startForeground أولًا في كل المسارات بلا استثناء — بما فيها
        // إعادة التشغيل بلا توكن (intent = null): العقد النظامي باقٍ على إعادة
        // التشغيل وهذا كان سبب حلقة «توقف عن العمل» (الشرح أعلى الملف).
        ensureChannel()
        val notification: Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_view)
                .setContentTitle(getString(R.string.guard_notification_title))
                .setContentText(getString(R.string.projection_notification_text))
                .setOngoing(true)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build()
        try {
            // نوع mediaProjection شرط نظامي على API 29+ — وعلى API 28 يكفي
            // startForeground العادي. على إعادة التشغيل بلا جلسة حية قد يرفض
            // النوع النظامي لدى بعض الأغلفة — الاستدعاء بلا نوع ملاذ آمن يفي
            // بالعقد ويمنع الانهيار في كل الحالات.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this, NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            try { startForeground(NOTIFICATION_ID, notification) } catch (_: Throwable) {}
        }

        if (intent == null) {
            // [0.3.3] أعاد النظام الخدمة بعد موت العملية (START_STICKY) — التوكن
            // مات مع العملية بحكم النظام (لا يُخزَّن أبدًا). العقد وفّيه أعلاه فلا
            // انهيار؛ الآن الإنقاذ (استرداد صفري أو إشعار بنقرة) ثم توقف هادئ:
            // START_NOT_STICKY + stopSelf — الاستعادة تعيد تشغيلنا بتصريح حي
            // عبر ProjectionService.start، وخدمة بلا تصريح لا معنى لبقائها.
            GuardLog.add("أعاد النظام الخدمة بعد موت العملية — بدء إنقاذ الجلسة فورًا")
            RecoveryNotifier.maybeNotify(this)
            stopSelf()
            return START_NOT_STICKY
        }
        val rc = intent.getIntExtra("resultCode", Activity.RESULT_CANCELED)
        @Suppress("DEPRECATION")
        val data = intent.getParcelableExtra<Intent>("data")
        if (data == null) {
            // إطلاق بلا توكن (عطل في النداء) — ننهي بهدوء بدل خدمة معلقة بلا نوع
            stopSelf()
            return START_NOT_STICKY
        }

        ProjectionCaptureEngine.start(applicationContext, rc, data)
        GuardLog.add("خدمة العرض الأمامية بدأت — محرك الالتقاط يُنشأ الآن")
        // [0.3.3] الإنقاذ الذاتي: حين تسقط الجلسة الحيّة (نقرة إيقاف/قتل النظام)
        // يبدأ الإنقاذ لحظتها — استرداد صفري بلا لمستك (أو إشعار بنقرة إن أوقفته
        // بيدك)، بشرط canGuard وبدون تكرار داخل نافذة 60 ث.
        ProjectionCaptureEngine.onSessionLost = {
            RecoveryNotifier.maybeNotify(this@ProjectionService)
        }
        // [0.3.3] START_STICKY: قتل العملية يعيد الخدمة تلقائيًا — ومحاولة
        // إعادة التشغيل الصامتة تمر أعلاه بمسار الإنقاذ لا بالصمت.
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // [0.3.3] وعد «لا إيقاف أبدًا إلا بيدك»: مسح التطبيق من «الأخيرة» لا
        // يوقف الحماية — الخدمة الأمامية تكمل عملها، وأي موت لاحق للعملية
        // يعالجه START_STICKY + الإنقاذ الذاتي (ملاحظة: بعض أغلفة المصنّعين
        // كسامسونج تقتل العملية كلها عند المسح — عندها يتكفل مسار الإنقاذ نفسه).
        GuardLog.add("أُزيل التطبيق من «الأخيرة» — الحماية تكمل عملها (إيقافها بيدك حصريًا)")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        ProjectionCaptureEngine.stop()
        GuardLog.add("خدمة العرض توقفت — مسار الالتقاط البديل مُفرَّغ")
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
