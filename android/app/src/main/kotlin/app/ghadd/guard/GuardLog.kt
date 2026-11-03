package app.ghadd.guard

import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale

/**
 * سجل تشخيصي في الذاكرة فقط (آخر 50 حدثًا) — يعرض في شاشة التشخيص داخل التطبيق
 * ليحقق مبدأ «الشفافية المطلقة»: المستخدم يرى بأم عينه ماذا يفعل المحرك لحظة بلحظة.
 * لا يُكتب على القرص ولا يغادر الجهاز إطلاقًا، ويُمسح بموت العملية.
 */
object GuardLog {
    private const val MAX = 50
    private val lines = ArrayDeque<String>(MAX)
    private val fmt = SimpleDateFormat("HH:mm:ss", Locale.US)

    @Synchronized
    fun add(message: String) {
        if (lines.size >= MAX) lines.removeFirst()
        lines.addLast("${fmt.format(Date())} — $message")
    }

    @Synchronized
    fun all(): List<String> = lines.toList()
}
