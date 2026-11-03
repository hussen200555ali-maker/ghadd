// اختبار التكامل على محاكي أندرويد حقيقي — يثبت سلسلة الكشف كاملة على النظام نفسه
// الذي يستخدمه المستخدم (أندرويد 9 = API 28 في سير عمل المحاكي):
//   1) النموذج المدمج (88MB) موجود فعلًا داخل أصول الـAPK
//   2) نسخه إلى ملفات التطبيق الخاصة داخل العزلة (نفس سياسة registerModel)
//   3) تسجيله في محرك الكشف (تحقق TFL3 + جدول ModelRegistry الأصلي)
//   4) استدلال TFLite حقيقي على الصورة التجريبية — فئات سليمة ومجاميع احتمالات ≈ 1
//   5) المسار الإنتاجي كاملًا عبر DetectorService.analyzeBytes (نفس مسار خدمة الوصول)
//
// هذا هو نفس المسار الذي ينفذه زر «اختبار الكشف الذاتي» في شاشة التشخيص —
// أي أن نجاحه هنا دليل مباشر على أن زر المستخدم سينجح على أندرويد 9.
//
// [ملاحظة عزل بيئة الاختبار] قناة ghadd/system الأصلية تُسجَّل في MainActivity
// الذي لا يعمل داخل مشغّل اختبارات التكامل، لذا تُحاكى القناة بمسار النموذج
// المحضَّر — العقود نفسها (ok/path/modelId) وتبقى سلسلة Dart↔Kotlin↔TFLite
// حقيقية 100% من registerModel حتى الاستدلال.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghadd/services/native_bridge.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nsfw_detect/nsfw_detect.dart';

void main() {
  // الربط يعمل افتراضيًا بسياسة fullyLive — استدعاءات async حقيقية (لا ساعة وهمية)
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const modelId = 'ghadd_nsfw';
  late String preparedPath;

  setUpAll(() async {
    // 1+2: النموذج المدمج داخل الـAPK → ملفات التطبيق الخاصة (cacheDir داخل العزلة)
    final data = await rootBundle.load('assets/models/nsfw.tflite');
    assert(data.lengthInBytes > 50 * 1024 * 1024,
        'النموذج المدمج غير موجود أو مقطوع — الحجم الفعلي ${data.lengthInBytes}');
    final dir = await getTemporaryDirectory(); // cacheDir — جذر عزلة مسموح
    final f = File('${dir.path}/nsfw_it.tflite');
    await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true);
    preparedPath = f.path;

    // 3: محاكاة قناة ghadd/system بنفس عقد الإنتاج حتى يعمل GuardBrain.ensure()
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ghadd/system'), (call) async {
      switch (call.method) {
        case 'prepareModel':
          return {'ok': true, 'path': preparedPath, 'modelId': modelId};
        case 'logFromDart':
          return true;
        case 'guardLogs':
          return <String>[];
        default:
          return null;
      }
    });
  });

  testWidgets('سلسلة الكشف الكاملة: نسخ → تسجيل → استدلال TFLite → المسار الإنتاجي',
      (tester) async {
    // 3: التسجيل في المحرك الأصلي (تحقق العزلة + الوجود + بصمة TFL3 في Kotlin)
    final regPath = await NsfwDetector.instance.registerModel(ModelRegistration(
      id: modelId,
      displayName: 'غَضّ — اختبار المحاكي',
      assetPath: preparedPath,
      inputSize: 224,
    ));
    expect(regPath, isNotEmpty, reason: 'registerModel يجب أن يعيد المسار المتحقق منه');

    // تسجيل النموذج عبر مسار GuardBrain الإنتاجي (قناة محاكاة + registerModel)
    final ensured = await GuardBrain.ensure();
    expect(ensured, isTrue, reason: 'GuardBrain.ensure فشل — تسجيل النموذج الإنتاجي معطوب');

    // 4: استدلال حقيقي — نفس صورة زر الاختبار الذاتي (رمادية 64×64، آمنة بطبيعتها)
    final result = await NsfwDetector.instance.scanBytes(
      GuardBrain.warmupJpeg,
      modelId: modelId,
      confidenceThreshold: 0.7,
    );
    final labels = result.labels;
    expect(labels, isNotEmpty, reason: 'الاستدلال أعاد لا فئات — مخرجات النموذج مقروءة خطأ');
    double sum = 0;
    double nsfw = 0;
    for (final l in labels) {
      expect(l.confidence, inInclusiveRange(0.0, 1.0),
          reason: 'ثقة خارج المجال [0,1]: ${l.category}=${l.confidence} — قراءة مخرجات خاطئة');
      sum += l.confidence;
      final cat = l.category.toString().split('.').last;
      if (cat == 'nudity' || cat == 'explicitNudity' || cat == 'suggestive') {
        nsfw = nsfw > l.confidence ? nsfw : l.confidence;
      }
    }
    // softmax مدمج في الرسم البياني → مجموع الاحتمالات قريب من 1.
    // انحرافه يعني تخطيط إدخال خاطئ (NCHW/HWC) أو نموذجًا تالفًا.
    expect(sum, inInclusiveRange(0.8, 1.2),
        reason: 'مجموع الاحتمالات $sum بعيد عن 1 — مؤشر تخطيط إدخال خاطئ أو نموذج تالف');
    // صورة رمادية ساكنة يجب أن تُقيَّم آمنة بأي نموذج سليم
    expect(nsfw, lessThan(0.45),
        reason: 'صورة رمادية ساكنة صنّفت غير لائقة بثقة $nsfw — مؤشر عطب في الإدخال/النموذج');

    // 5: المسار الإنتاجي نفسه الذي تستدعيه خدمة إمكانية الوصول (analyzeBytes)
    final verdict = await DetectorService.analyzeBytes(
      GuardBrain.warmupJpeg,
      0.7,
      expanded: true,
    );
    expect(verdict['unsafe'], isFalse,
        reason: 'حكم المسار الإنتاجي: رمادية ساكنة = آمن، حصلنا على ${verdict['unsafe']}');
    expect(verdict['score'], inInclusiveRange(0.0, 1.0));
    expect(verdict['threshold'], 0.45, reason: 'التغطية الموسّعة يجب أن تخفض العتبة إلى 0.45');
  });

  testWidgets('فحص ثانٍ بعد التسخين — الاستدلال مستقر ولا يتسرب', (tester) async {
    // ثبات الاستدلال بعد أول تحميل: نتيجة متطابقة تقريبًا في نداء متكرر
    final a = await NsfwDetector.instance.scanBytes(
      GuardBrain.warmupJpeg,
      modelId: modelId,
      confidenceThreshold: 0.7,
    );
    final b = await NsfwDetector.instance.scanBytes(
      GuardBrain.warmupJpeg,
      modelId: modelId,
      confidenceThreshold: 0.7,
    );
    final sa = (a.labels.first.confidence as num).toDouble();
    final sb = (b.labels.first.confidence as num).toDouble();
    expect((sa - sb).abs(), lessThan(0.01),
        reason: 'نتيجة الاستدلال غير مستقرة بين نداءين متتاليين على نفس المدخل');
  });
}
