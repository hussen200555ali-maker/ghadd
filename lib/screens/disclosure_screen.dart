import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../services/native_bridge.dart';

/// شاشة الترحيب والإفصاح البارز (مخطط الواجهة 1 من 4 — وثيقة الردّ التقني ص8).
/// بوابة التطبيق بأكمله: الإفصاح قبل أي صلاحية، والموافقة صريحة غير مجمّعة،
/// وزر المتابعة معطّل برمجيًا حتى التحديد. الإلغاء متاح دائمًا بلا عقوبة.
class DisclosureScreen extends StatefulWidget {
  const DisclosureScreen({super.key, required this.onDone});

  /// يُستدعى بعد تسجيل الموافقة ومزامنتها مع المرآة الأصلية.
  final VoidCallback onDone;

  @override
  State<DisclosureScreen> createState() => _DisclosureScreenState();
}

class _DisclosureScreenState extends State<DisclosureScreen> {
  bool _agreed = false;

  Future<void> _continue() async {
    if (!_agreed) return;
    GuardSettings.consent = true;
    await GuardSettings.sync(); // تصل الموافقة إلى GuardPrefs.canGuard في Kotlin
    // آخر خطوة لا تُستبق: صفحة إمكانية الوصول تُفتح فقط بعد الموافقة.
    await GuardSystem.openAccessibilitySettings();
    widget.onDone();
  }

  void _showFullText() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('النص الكامل للإفصاح',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Text(
            'ما يفعله غَضّ:\n'
            '• يلتقط لقطة للشاشة عند تغيّر محتواها، ويحللها على جهازك بالكامل '
            'بنموذج مدمج (nsfw_detect)، ثم يغطي الشاشة إذا كان المحتوى غير لائق.\n'
            '• يحتفظ بأرقام مجردة في عدادات محلية (كم شاشة خُفيت) — بلا صور ولا نصوص.\n\n'
            'ما لن يفعله غَضّ أبدًا:\n'
            '• لا يملك صلاحية INTERNET في بيانه — لا يستطيع إرسال أي بايت خارج '
            'جهازك ولو أراد. تحقّق بنفسك: aapt2 dump badging app-release.apk.\n'
            '• لا يكتب اللقطة على القرص إطلاقًا: تُحلل في الذاكرة ثم تُحرَّر فورًا.\n'
            '• لا يخزّن، لا يشارك، لا يتتبع، ولا يبيع أي شيء — لا يوجد ما يُخزَّن.\n\n'
            'يمكنك إيقاف الحماية أو إلغاء الموافقة في أي وقت من التطبيق، '
            'وتعطيل خدمة الوصول من إعدادات النظام — الطوعية كاملة بلا استثناء.',
            style: TextStyle(height: 1.7, fontSize: 13.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: GuardTheme.page,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0 ? GuardTheme.teal : GuardTheme.border,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    border: Border.all(color: GuardTheme.teal, width: 2.5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: const Text('غ',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: GuardTheme.tealDeep)),
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text('أهلًا بك في غَضّ',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: GuardTheme.navy)),
              ),
              const Center(
                child: Text('حماية بصرية طوعية — على جهازك فقط',
                    style: TextStyle(color: GuardTheme.muted, fontSize: 13)),
              ),
              const SizedBox(height: 18),
              // بطاقة الإفصاح البارز: إطار فيروزي سميك — قبل أي صلاحية.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: GuardTheme.teal, width: 2.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('إفصاح بارز — اقرأه قبل التمكين',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: GuardTheme.tealDeep)),
                    const SizedBox(height: 10),
                    _row(true,
                        'يلتقط لقطات لشاشتك ويحللها محليًا لإخفاء المحتوى غير اللائق.'),
                    _row(true, 'يعمل دائمًا في الخلفية بخدمة إشعار دائم تظهر لك.'),
                    _row(false,
                        'لا يملك صلاحية الإنترنت — لا شيء يخرج من هاتفك، يمكنك التحقق بنفسك.'),
                    _row(false,
                        'لا يخزّن أي صورة أو نص على القرص — اللقطة تُحلل ثم تُحرَّر من الذاكرة.'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: CheckboxListTile(
                  value: _agreed,
                  activeColor: GuardTheme.tealDeep,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('قرأت الإفصاح وأوافق على تمكين الخدمة.',
                      style: TextStyle(fontSize: 13.5)),
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                ),
              ),
              const SizedBox(height: 14),
              // زر المتابعة معطّل حتى الموافقة الصريحة — لا موافقة مجمّعة.
              FilledButton(
                onPressed: _agreed ? _continue : null,
                style: FilledButton.styleFrom(
                  backgroundColor: GuardTheme.tealDeep,
                  disabledBackgroundColor: GuardTheme.card,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  _agreed ? 'متابعة إلى إعدادات إمكانية الوصول' : 'حدّد مربع الموافقة للمتابعة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _agreed ? Colors.white : GuardTheme.muted,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _showFullText,
                    child: const Text('النص الكامل للإفصاح',
                        style: TextStyle(color: GuardTheme.muted, fontSize: 12.5)),
                  ),
                  const Text('·', style: TextStyle(color: GuardTheme.muted)),
                  TextButton(
                    onPressed: () =>
                        SystemNavigator.pop(), // الإلغاء متاح بلا عقوبة
                    child: const Text('إلغاء',
                        style: TextStyle(color: GuardTheme.muted, fontSize: 12.5)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'الخطوة 1 من 3 — بعد الموافقة تُفتح صفحة إمكانية الوصول مباشرة',
                  style: TextStyle(color: GuardTheme.muted, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(bool positive, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            positive ? '✓' : '✗',
            style: TextStyle(
              color: positive ? GuardTheme.tealDeep : const Color(0xFFB04A4A),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.8, height: 1.6)),
          ),
        ],
      ),
    );
  }
}
