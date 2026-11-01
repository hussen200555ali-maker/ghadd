package app.ghadd.guard

import android.content.Context
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager

/**
 * طبقة الاستجابة: تغطية كاملة النافذة عند كشف غير آمن (القسم 4.1، الطبقة الثالثة).
 * تختفي تلقائيًا بعد مهلة أو بنقرة المستخدم.
 */
object OverlayController {

    private const val AUTO_HIDE_MS = 8000L
    private var current: View? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun show(context: Context) {
        mainHandler.post { showInternal(context.applicationContext) }
    }

    private fun showInternal(context: Context) {
        if (!Settings.canDrawOverlays(context)) return
        if (current != null) return

        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val view = LayoutInflater.from(context).inflate(R.layout.overlay_block, null)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        try {
            wm.addView(view, params)
            current = view
            view.setOnClickListener { hide(context) }
            mainHandler.postDelayed({ hide(context) }, AUTO_HIDE_MS)
        } catch (_: Throwable) {
        }
    }

    fun hide(context: Context) {
        mainHandler.post {
            val v = current ?: return@post
            try {
                (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                    .removeView(v)
            } catch (_: Throwable) {
            }
            current = null
        }
    }
}
