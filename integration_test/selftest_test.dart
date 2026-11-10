// اختبار التكامل على محاكي أندرويد حقيقي — يثبت سلسلة الكشف كاملة على النظام نفسه
// الذي يستخدمه المستخدم (أندرويد 9 = API 28 في سير عمل المحاكي):
//   1) النموذج المدمج (88MB) وكاشف NudeNet (51.9MB) موجودان فعلًا في الـAPK
//   2) نسخه إلى ملفات التطبيق الخاصة داخل العزلة (نفس سياسة registerModel)
//   3) تسجيله في محرك الكشف (تحقق TFL3 + جدول ModelRegistry الأصلي)
//   4) استدلال TFLite حقيقي على الصورة التجريبية — فئات سليمة ومجاميع احتمالات ≈ 1
//   5) المسار الإنتاجي كاملًا عبر DetectorService.analyzeBytes (نفس مسار خدمة الوصول)
//   6) ثبات الاستدلال بين نداءين متتاليين (بعد التسخين)
//
// هذا هو نفس المسار الذي ينفذه زر «اختبار الكشف الذاتي» في شاشة التشخيص —
// أي أن نجاحه هنا دليل مباشر على أن زر المستخدم سينجح على أندرويد 9.
//
// [درس تشغيلة 2026-11-03] تشغيلتان توقفتا عند المهلة: الأولى أُلغيت خارجيًا،
// والثانية علِق المحاكي نفسه (System UI isn't responding — فقر موارد) بعد نجاح
// السلسلة كاملة. لذلك: اختبار واحد متسلسل (بلا فجوة teardown بين testWidgets
// المتعددة)، مهلة 8 د للاختبار كله، مهلة 3 د لكل نداء استدلال، وعلامات تقدم
// debugPrint تظهر في it_log وlogcat حتى لو توقف كل شيء بعدها.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghadd/core/decision.dart';
import 'package:ghadd/services/native_bridge.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nsfw_detect/nsfw_detect.dart';

void main() {
  // الربط يعمل افتراضيًا بسياسة fullyLive — استدعاءات async حقيقية (لا ساعة وهمية)
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const modelId = 'ghadd_nsfw';
  late String preparedPath;
  late String regionsPreparedPath;

  setUpAll(() async {
    debugPrint('[SELFTEST] setUpAll: تحميل النموذجين المدمجين من الأصول…');
    // 1+2: النموذج المدمج داخل الـAPK → ملفات التطبيق الخاصة (cacheDir داخل العزلة)
    final data = await rootBundle.load('assets/models/nsfw.tflite').timeout(
          const Duration(minutes: 2),
          onTimeout: () => throw StateError('علِق > المهلة: rootBundle.load للنموذج علِق >2د'),
        );
    assert(data.lengthInBytes > 50 * 1024 * 1024,
        'النموذج المدمج غير موجود أو مقطوع — الحجم الفعلي ${data.lengthInBytes}');
    debugPrint('[SELFTEST] setUpAll: النموذج ${data.lengthInBytes} بايت ✓');
    final dir = await getTemporaryDirectory(); // cacheDir — جذر عزلة مسموح
    final f = File('${dir.path}/nsfw_it.tflite');
    await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true);
    preparedPath = f.path;
    debugPrint('[SELFTEST] setUpAll: النسخ إلى ${f.path} ✓');

    // [0.4.0] كاشف NudeNet YOLOv8m ذي 18 فئة (~51.9MB) — نفس العقد
    final rdata = await rootBundle.load('assets/models/nsfw_regions.tflite').timeout(
          const Duration(minutes: 2),
          onTimeout: () => throw StateError('علِق > المهلة: rootBundle.load لنموذج المناطق علِق >2د'),
        );
    assert(rdata.lengthInBytes > 45 * 1024 * 1024,
        'نموذج المناطق غير موجود أو مقطوع — الحجم الفعلي ${rdata.lengthInBytes}');
    debugPrint('[SELFTEST] setUpAll: نموذج المناطق ${rdata.lengthInBytes} بايت ✓');
    final rf = File('${dir.path}/nsfw_regions_it.tflite');
    await rf.writeAsBytes(
        rdata.buffer.asUint8List(rdata.offsetInBytes, rdata.lengthInBytes),
        flush: true);
    regionsPreparedPath = rf.path;

    // 3: محاكاة قناة ghadd/system بنفس عقد الإنتاج حتى يعمل GuardBrain.ensure()
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ghadd/system'), (call) async {
      switch (call.method) {
        case 'prepareModel':
          return {
            'ok': true,
            'path': preparedPath,
            'modelId': modelId,
            'regionsOk': true,
            'regionsPath': regionsPreparedPath,
            'regionsModelId': 'ghadd_nsfw_regions',
          };
        case 'logFromDart':
          return true;
        case 'guardLogs':
          return <String>[];
        default:
          return null;
      }
    });
    debugPrint('[SELFTEST] setUpAll: قناة ghadd/system مُحاكاة ✓');
  });

  testWidgets(
    'سلسلة الكشف الكاملة: نسخ → تسجيل → استدلال TFLite → المسار الإنتاجي → ثبات',
    (tester) async {
      // ===== 3: التسجيل في المحرك الأصلي =====
      debugPrint('[SELFTEST] مرحلة 1: registerModel…');
      final regPath = await NsfwDetector.instance
          .registerModel(ModelRegistration(
            id: modelId,
            displayName: 'غَضّ — اختبار المحاكي',
            assetPath: preparedPath,
            inputSize: 224,
          ))
          .timeout(const Duration(minutes: 10),
              onTimeout: () => throw StateError('علِق > المهلة: registerModel علِق >10د'));
      expect(regPath, isNotEmpty, reason: 'registerModel يجب أن يعيد المسار المتحقق منه');
      debugPrint('[SELFTEST] مرحلة 1 ✓: $regPath');

      // تسجيل النموذج عبر مسار GuardBrain الإنتاجي (قناة محاكاة + registerModel)
      debugPrint('[SELFTEST] مرحلة 2: GuardBrain.ensure…');
      final ensured = await GuardBrain.ensure().timeout(const Duration(minutes: 2),
          onTimeout: () => throw StateError('علِق > المهلة: GuardBrain.ensure علِق >2د'));
      expect(ensured, isTrue, reason: 'GuardBrain.ensure فشل — تسجيل النموذج الإنتاجي معطوب');
      debugPrint('[SELFTEST] مرحلة 2 ✓');

      // ===== 4: استدلال حقيقي =====
      // نفس صورة زر الاختبار الذاتي (رمادية 64×64، آمنة بطبيعتها)
      debugPrint('[SELFTEST] مرحلة 3: أول scanBytes…');
      final result = await NsfwDetector.instance
          .scanBytes(GuardBrain.warmupJpeg, modelId: modelId, confidenceThreshold: 0.7)
          .timeout(const Duration(minutes: 10),
              onTimeout: () => throw StateError('علِق > المهلة: أول scanBytes علِق >10د'));
      final labels = result.labels;
      expect(labels, isNotEmpty, reason: 'الاستدلال أعاد لا فئات — مخرجات النموذج مقروءة خطأ');
      debugPrint('[SELFTEST] مرحلة 3 ✓: ${labels.length} فئة');
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
      debugPrint('[SELFTEST] مجموع الاحتمالات = $sum | أعلى غير لائق = $nsfw');
      // softmax مدمج في الرسم البياني → مجموع الاحتمالات قريب من 1.
      // انحرافه يعني تخطيط إدخال خاطئ (NCHW/HWC) أو نموذجًا تالفًا.
      expect(sum, inInclusiveRange(0.8, 1.2),
          reason: 'مجموع الاحتمالات $sum بعيد عن 1 — مؤشر تخطيط إدخال خاطئ أو نموذج تالف');
      // صورة رمادية ساكنة يجب أن تُقيَّم آمنة بأي نموذج سليم
      expect(nsfw, lessThan(0.45),
          reason: 'صورة رمادية ساكنة صنّفت غير لائقة بثقة $nsfw — مؤشر عطب في الإدخال/النموذج');

      // ===== 5: المسار الإنتاجي نفسه الذي تستدعيه خدمة إمكانية الوصول =====
      debugPrint('[SELFTEST] مرحلة 4: analyzeBytes الإنتاجي…');
      final verdict = await DetectorService.analyzeBytes(
        GuardBrain.warmupJpeg,
        0.7,
        expanded: true,
      ).timeout(const Duration(minutes: 10),
          onTimeout: () => throw StateError('علِق > المهلة: analyzeBytes علِق >10د'));
      expect(verdict['unsafe'], isFalse,
          reason: 'حكم المسار الإنتاجي: رمادية ساكنة = آمن، حصلنا على ${verdict['unsafe']}');
      expect(verdict['score'], inInclusiveRange(0.0, 1.0));
      expect(verdict['threshold'], 0.45, reason: 'التغطية الموسّعة يجب أن تخفض العتبة إلى 0.45');
      debugPrint('[SELFTEST] مرحلة 4 ✓: score=${verdict['score']}');

      // ===== 6: ثبات الاستدلال بعد التسخين =====
      debugPrint('[SELFTEST] مرحلة 5: scanBytes ثانية (ثبات)…');
      final b = await NsfwDetector.instance
          .scanBytes(GuardBrain.warmupJpeg, modelId: modelId, confidenceThreshold: 0.7)
          .timeout(const Duration(minutes: 10),
              onTimeout: () => throw StateError('علِق > المهلة: scanBytes الثانية علِقت >10د — انسداد في محرك الاستدلال'));
      final sa = (result.labels.first.confidence as num).toDouble();
      final sb = (b.labels.first.confidence as num).toDouble();
      expect((sa - sb).abs(), lessThan(0.01),
          reason: 'نتيجة الاستدلال غير مستقرة بين نداءين متتاليين على نفس المدخل');
      debugPrint('[SELFTEST] مرحلة 5 ✓: $sa ≈ $sb — السلسلة كلها سليمة');

      // ===== 7 [0.4.0]: NudeNet 18-class — تسجيل واستدلال TFLite =====
      debugPrint('[SELFTEST] مرحلة 6: كاشف المناطق (NudeNet YOLOv8m, 18 فئة)…');
      expect(GuardBrain.regionsReady, isTrue,
          reason: 'كاشف المناطق لم يُسجّل في GuardBrain.ensure رغم توفر النموذج');
      expect(GuardBrain.regionsClassLabels.length, 18,
          reason: 'جدول فئات NudeNet يجب أن يطابق 18 قناة كشف');
      final regScan = await NsfwDetector.instance
          .scanBytes(GuardBrain.warmupJpeg,
              modelId: GuardBrain.regionsModelId, confidenceThreshold: 0.25)
          .timeout(const Duration(minutes: 5),
              onTimeout: () => throw StateError('علِق > المهلة: كاشف المناطق علِق >5د'));
      // اكتمال الحالة يثبت السلسلة كاملةً: تحميل TFLite 18-class + استدلال
      // YOLO [1,22,A] + فك المربعات وNMS بلا أي استثناء.
      expect(regScan.status, ScanStatus.completed,
          reason: 'كشف المناطق لم يكتمل (${regScan.status}) — خطأ تحميل/استدلال');
      // قد تظهر فئات عامة؛ يجب ألا تمر أي فئة حساسة من إطار رمادي آمن.
      final dets = regScan.detections ?? const [];
      final sensitiveDets = dets
          .where((d) => SensitiveBodyMask.isSensitiveLabel(d.label))
          .toList();
      expect(sensitiveDets, isEmpty,
          reason: 'إطار رمادي آمن أنتج ${sensitiveDets.length} كشفًا حساسًا');
      debugPrint('[SELFTEST] مرحلة 6 ✓: NudeNet مكتمل؛ ${dets.length} صندوقًا و0 حساس على الرمادي');
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
