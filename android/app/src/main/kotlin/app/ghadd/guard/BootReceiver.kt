package app.ghadd.guard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * [0.3.3] الاسترداد بعد إعادة الإقلاع — جزء من عهد «لا يوقفه النظام أبدًا».
 *
 * إعادة إقلاع الجهاز تقتل جلسة الالتقاط بحكم النظام (التوكن لا يُخزَّن
 * أصلًا — قرار خصوصية موثق)، لكن العمى بعدها ليس قدرًا: هذا المستقبل (بث
 * محمي لا يرسله النظام إلا نفسه) يبدأ الإنقاذ لحظة الإقلاع إن كانت الحماية
 * مفعّلة بيدك:
 *  - إشعار الحالة الدائم يعود (خدمة أمامية من جديد).
 *  - الاسترداد الصفري يفتح حوار النظام ويؤكَّد آليًا (أو إشعار الإنقاذ إن
 *    أوقفتَ الاسترداد التلقائي بيدك).
 * ومفتاحك المقفل هو الفيصل: canGuard=false → لا شيء يبدأ إطلاقًا.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!GuardPrefs.canGuard(context)) return // الحماية مقفلة بيدك — لا شيء يبدأ
        GuardLog.add("أُعيد إقلاع الجهاز و«الحماية الآن» مفعّلة بيدك — بدء الإنقاذ تلقائيًا")
        // إشعار الحالة الدائم يعود أولًا — صدق الحالة قبل أي شيء
        try {
            GuardForegroundService.start(context)
        } catch (_: Throwable) { /* الإنقاذ لا يتوقف بسبب الإشعار */ }
        RecoveryNotifier.maybeNotify(context)
    }
}
