import 'package:flutter/material.dart';

import 'app.dart';
import 'services/native_bridge.dart';

void main() {
  runApp(const GhaddApp());
}

/// نقطة الدخول الخلفية لمحرك الكشف: تُشغَّل داخل FlutterEngine مخصص تستدعيه
/// خدمة إمكانية الوصول (GuardAccessibilityService.ensureEngine).
/// لا واجهة هنا — فقط الاستماع لطلبات التحليل وتنفيذها محليًا عبر nsfw_detect.
@pragma('vm:entry-point')
void guardMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DetectorChannel.registerHandler();
}
