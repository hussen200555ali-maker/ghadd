import 'package:flutter/material.dart';

import 'app.dart';
import 'services/native_bridge.dart';

void main() {
  runApp(const GhaddApp());
}

/// نقطة الدخول الخلفية لمحرك الكشف: تُشغَّل داخل FlutterEngine مخصص تستدعيه
/// خدمة إمكانية الوصول (GuardAccessibilityService.ensureEngine).
/// لا واجهة هنا — فقط تجهيز النموذج المدمج والاستماع لطلبات التحليل.
@pragma('vm:entry-point')
void guardMain() {
  WidgetsFlutterBinding.ensureInitialized();
  // الإصلاح الجذري: النموذج المدمج يجب أن يكون مسجلاً قبل أول نداء analyze —
  // بدونه كان الفحص يفشل دائمًا (النموذج الافتراضي يحتاج تنزيلًا من الشبكة).
  GuardBrain.ensure().then((ok) async {
    if (ok) await GuardBrain.warmUp();
  });
  DetectorChannel.registerHandler();
}
