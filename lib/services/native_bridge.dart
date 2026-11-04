import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nsfw_detect/nsfw_detect.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/decision.dart';

/// تخزين محلي فقط — أي مفتاح هنا بمرآته في GuardPrefs.kt عبر قناة ghadd/control،
/// ومرآة ثانية في shared_preferences (بادئة ghadd_) لاستعادة الحالة عند الإقلاع.
class GuardSettings {
  GuardSettings._();

  /// موافقة الإفصاح البارز — البوابة الوجودية: بلاها لا تُعرض الشاشة الرئيسية
  /// ولا تعمل خدمة الوصول أصلًا (canGuard = consent && enabled).
  static bool consent = false;
  static bool enabled = false;
  // المستوى المتوازن افتراضيًا (القسم 4.2: 0.85 صارم / 0.7 متوازن / 0.5 متساهل)
  static double threshold = 0.7;
  static List<String> whitelist = [];

  /// التغطية الموسّعة (مفعّلة افتراضيًا بطلب مالك التطبيق): تخفض حد الكشف
  /// الفعلي إلى 0.45 ليمسك المحتوى غير المحتشم (أجساد مكشوفة) وليس الصريح فقط —
  /// مقابل احتمال إزعاج أعلى. قابلة للإيقاف من الإعدادات.
  static bool expandedCoverage = true;

  /// [0.3.0] وضع المناطق (افتراضي: مفعّل — تجربة المستخدم المثالية): عند الكشف
  /// تُغطى المربعات المكتشفة فقط بلا مانع لمس — فيواصل المستخدم عمله كالمعتاد —
  /// مع التغطية الكاملة احتياطًا عند تعذر تحديد المواضع. مرآته GuardPrefs.regionMode.
  static bool regionMode = true;

  static const _channel = MethodChannel('ghadd/control');

  /// استعادة الحالة من التفضيلات المحلية عند الإقلاع (قبل أي عرض للواجهة).
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    consent = p.getBool('ghadd_consent') ?? false;
    enabled = p.getBool('ghadd_enabled') ?? false;
    threshold = p.getDouble('ghadd_threshold') ?? 0.7;
    whitelist = p.getStringList('ghadd_whitelist') ?? const [];
    expandedCoverage = p.getBool('ghadd_expanded') ?? true;
    regionMode = p.getBool('ghadd_region_mode') ?? true;
  }

  /// يدفع الإعدادات كاملة إلى المرآتين (محلية + أصلية) بعد أي تعديل.
  static Future<void> sync() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('ghadd_consent', consent);
    await p.setBool('ghadd_enabled', enabled);
    await p.setDouble('ghadd_threshold', threshold);
    await p.setStringList('ghadd_whitelist', whitelist);
    await p.setBool('ghadd_expanded', expandedCoverage);
    await p.setBool('ghadd_region_mode', regionMode);
    try {
      await _channel.invokeMethod('sync', {
        'consent': consent,
        'enabled': enabled,
        'threshold': threshold,
        'whitelist': whitelist,
        'expanded': expandedCoverage,
        'regionMode': regionMode,
      });
    } on PlatformException {
      // النموذج الأولي: نتجاهل بهدوء إن لم تكن الطبقة الأصلية جاهزة بعد
    }
  }

  static Future<Map<String, dynamic>> stats() async {
    try {
      final raw = await _channel.invokeMethod('stats');
      return Map<String, dynamic>.from(raw as Map);
    } on PlatformException {
      return {
        'blocked_total': 0,
        'blocked_today': 0,
        'last_blocked_at': '',
        'last_blocked_app': '',
      };
    }
  }
}

/// قنوات النظام: بدء/إيقاف الخدمة الدائمة وفتح شاشات المنح.
class GuardSystem {
  static const _channel = MethodChannel('ghadd/system');

  static Future<void> startGuard() async {
    try { await _channel.invokeMethod('startGuard'); } on PlatformException {/* تجاهل مقصود — القناة الأصلية غير متاحة في بيئات الاختبار */}
  }

  static Future<void> stopGuard() async {
    try { await _channel.invokeMethod('stopGuard'); } on PlatformException {/* تجاهل مقصود — القناة الأصلية غير متاحة في بيئات الاختبار */}
  }

  static Future<void> openAccessibilitySettings() async {
    try { await _channel.invokeMethod('openAccessibilitySettings'); } on PlatformException {/* تجاهل مقصود — القناة الأصلية غير متاحة في بيئات الاختبار */}
  }

  static Future<void> openOverlaySettings() async {
    try { await _channel.invokeMethod('openOverlaySettings'); } on PlatformException {/* تجاهل مقصود — القناة الأصلية غير متاحة في بيئات الاختبار */}
  }

  /// حالة مسار الالتقاط البديل (أندرويد 9/10):
  /// legacy = الجهاز يحتاج تصريح عرض الشاشة، active = التصريح منح والمحرك يعمل الآن.
  static Future<Map<String, dynamic>> projectionStatus() async {
    try {
      final raw = await _channel.invokeMethod('projectionStatus');
      return Map<String, dynamic>.from(raw as Map);
    } on PlatformException {
      return const {'legacy': false, 'active': false};
    } on MissingPluginException {
      return const {'legacy': false, 'active': false};
    }
  }

  /// [0.3.2] حالة مقاومة النوم من النظام مباشرة:
  /// exempt = التطبيق مستثنى من تحسين البطارية وDoze (أول درع ضد قتل
  /// سامسونج للعملية النائمة ومعها جلسة الالتقاط)، sdk = إصدار النظام.
  static Future<Map<String, dynamic>> batteryStatus() async {
    try {
      final raw = await _channel.invokeMethod('batteryStatus');
      return Map<String, dynamic>.from(raw as Map);
    } on PlatformException {
      return const {'exempt': false, 'sdk': 0};
    } on MissingPluginException {
      return const {'exempt': false, 'sdk': 0};
    }
  }

  /// [0.3.2] يفتح حوار النظام «السماح لغَضّ بالعمل دائمًا في الخلفية؟» —
  /// المنح بيدك حصريًا (لا صامت أبدًا). exempt=true يعني مستثنى مسبقًا،
  /// opened=true يعني فُتح الحوار/القائمة وعند العودة تُقرأ الحالة الجديدة.
  static Future<Map<String, dynamic>> requestBatteryExemption() async {
    try {
      final raw = await _channel.invokeMethod('requestBatteryExemption');
      return Map<String, dynamic>.from(raw as Map);
    } on PlatformException {
      return const {'exempt': false, 'opened': false};
    } on MissingPluginException {
      return const {'exempt': false, 'opened': false};
    }
  }

  /// [0.3.3] فتح شاشة إدارة طاقة التطبيقات لدى المصنّع (سامسونج) مباشرة —
  /// الطبقة الخاصة «وضع التطبيقات النائمة» التي لا يغطيها استثناء 0.3.2.
  /// how: samsung_battery (شاشة سامسونج) / app_info (صفحة التطبيق — زر البطارية)
  /// / failed. opened=false يعني فشل كل المسارات.
  static Future<Map<String, dynamic>> openVendorBatterySettings() async {
    try {
      final raw = await _channel.invokeMethod('openVendorBatterySettings');
      return Map<String, dynamic>.from(raw as Map);
    } on PlatformException {
      return const {'opened': false, 'how': 'failed'};
    } on MissingPluginException {
      return const {'opened': false, 'how': 'failed'};
    }
  }

  /// [0.3.3] حالة الاسترداد الصفري: هل سقوط جلسة الالتقاط يُعالَج بلا لمسة
  /// منك؟ (يُفتح حوار النظام لحظتها ويؤكَّد آليًا عبر خدمة الوصول — نفس
  /// موافقتك السابقة). افتراضيًا مفعّل.
  static Future<bool> autoRecoveryStatus() async {
    try {
      final raw = await _channel.invokeMethod('autoRecoveryStatus');
      return raw is Map && raw['enabled'] == true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// [0.3.3] تفعيل/إيقاف الاسترداد الصفري بيدك. إيقافه يعيد الإنقاذ
  /// بإشعار heads-up تنقره (مسار الإنقاذ بنقرة واحدة).
  static Future<void> setAutoRecovery(bool value) async {
    try {
      await _channel.invokeMethod('setAutoRecovery', value);
    } on PlatformException {
      /* تجاهل مقصود — القناة الأصلية غير متاحة في بيئات الاختبار */
    } on MissingPluginException {
      /* كذلك */
    }
  }

  /// الحالة الحقيقية للصلاحيات من النظام (لا ذاكرة الواجهة):
  /// accessibility = خدمة الوصول مُفعّلة فعلًا في الإعدادات الآمنة،
  /// overlay = العرض فوق التطبيقات ممنوح، sdk = إصدار النظام للتفرعات.
  static Future<Map<String, dynamic>> permissionStatus() async {
    try {
      final raw = await _channel.invokeMethod('permissionStatus');
      return Map<String, dynamic>.from(raw as Map);
    } on PlatformException {
      return const {'accessibility': false, 'overlay': false, 'sdk': 0};
    } on MissingPluginException {
      return const {'accessibility': false, 'overlay': false, 'sdk': 0};
    }
  }

  /// يفتح حوار تصريح عرض الشاشة (حوار النظام نفسه) وعند المنح
  /// تبدأ الخدمة الأمامية وتُشغّل محرك الالتقاط البديل.
  static Future<void> startProjection() async {
    try {
      await _channel.invokeMethod('startProjection');
    } on PlatformException {/* تجاهل مقصود — القناة الأصلية غير متاحة في بيئات الاختبار */}
  }

  /// تجهيز النموذج المدمج: نسخ من أصول الـAPK إلى ملفات التطبيق
  /// (لا شبكة إطلاقًا) وإرجاع المسار لتسجيله في الحزمة.
  static Future<Map<String, dynamic>> prepareModel() async {
    try {
      final raw = await _channel.invokeMethod('prepareModel');
      return Map<String, dynamic>.from(raw as Map);
    } on PlatformException {
      return const {'ok': false, 'path': '', 'modelId': ''};
    } on MissingPluginException {
      return const {'ok': false, 'path': '', 'modelId': ''};
    }
  }

  /// سجلات التشخيص الأصلية (ذاكرة فقط) — شفافية كاملة للمستخدم.
  static Future<List<String>> guardLogs() async {
    try {
      final raw = await _channel.invokeMethod('guardLogs');
      return (raw as List).map((e) => e.toString()).toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// كتابة حدث من Dart إلى السجل الأصلي.
  static Future<void> logNative(String message) async {
    try {
      await _channel.invokeMethod('logFromDart', message);
    } on PlatformException {
      /* بلا قناة أصلية (اختبار) — تجاهل */
    } on MissingPluginException {
      /* كذلك */
    }
  }

  /// اختبار مباشر لمسار الالتقاط (شاشة التشخيص).
  static Future<Map<String, dynamic>> testCapture() async {
    try {
      final raw = await _channel.invokeMethod('testCapture');
      return Map<String, dynamic>.from(raw as Map);
    } on PlatformException catch (e) {
      return {'ok': false, 'note': e.message ?? 'فشل النداء'};
    } on MissingPluginException {
      return const {'ok': false, 'note': 'القناة الأصلية غير متاحة'};
    }
  }
}

/// قناة الكشف: تستقبل نداءات الخدمة الأصلية (analyze) وتنفذها محليًا.
/// العقد: البايتات تصل JPEG جاهزة من الذاكرة الأصلية — لا مسار ملف إطلاقًا.
class DetectorChannel {
  static const _channel = MethodChannel('ghadd/analyze');

  static void registerHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'analyze') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final bytes = args['bytes'] as Uint8List;
        final threshold = (args['threshold'] as num?)?.toDouble() ?? GuardSettings.threshold;
        final expanded = args['expanded'] == true;
        return DetectorService.analyzeBytes(bytes, threshold, expanded: expanded);
      }
      throw MissingPluginException();
    });
  }
}

/// عقل الكشف: يضمن وجود النموذجين المدمجين (المصنّف + كاشف المناطق) ومسجّلين
/// في الحزمة قبل أي فحص. النموذجان داخل أصول الـAPK — يُنسخان مرة واحدة إلى
/// ملفات التطبيق ثم يُسجلان عبر registerModel. لا شبكة إطلاقًا.
///
/// [0.3.0] كاشف المناطق: EraX-NSFW YOLO11n (Apache 2.0) — مربعات مكشوفة
/// بإحداثيات مُطبَّعة، مُحوَّل TFLite ومتحقق رقميًا (IoU ‎0.93–0.96 مقابل
/// مرجع PyTorch). يُستخدم لتعيين مواضع المحتوى بعد إنذار المصنّف — لتغطية
/// المناطق فقط بدل الشاشة كاملة.
class GuardBrain {
  GuardBrain._();

  static const _modelId = 'ghadd_nsfw';
  static const _regionsModelId = 'ghadd_nsfw_regions';

  /// ترتيب فئات كاشف EraX مطابق لـnames dict للنموذج — لا يُعتمد عليه في
  /// الحُكم (الواجهة تستخدم aggregatedCategory) لكنه التزام توثيقي.
  static const regionsClassLabels = <String>[
    'anus', 'make_love', 'nipple', 'penis', 'vagina',
  ];

  static bool _ready = false;
  static bool _regionsReady = false;

  static String get modelId => _modelId;
  static String get regionsModelId => _regionsModelId;
  static bool get ready => _ready;
  static bool get regionsReady => _regionsReady;

  /// صورة اختبار 64×64 رمادية (JPEG مبني في الذاكرة) — للتسخين والفحص الذاتي.
  /// [إصلاح 0.2.3] الثابت السابق كان base64 تالفًا (طوله 917 حرفًا — ليس من
  /// مضاعفات الأربعة) فكان كل فحص ذاتي يفشل بـFormatException قبل الوصول
  /// إلى النموذج أصلًا. الثابت الحالي مولَّد ومُتحقق منه برمجيًا (طول 920،
  /// فك/تشفير مستدير، ترويسة FFD8 ونهاية FFD9) واختبار العقد يحميه في
  /// test/warmup_test.dart.
  static final Uint8List warmupJpeg = base64Decode(
      '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAUDBAQEAwUEBAQFBQUGBwwIBwcHBw8LCwkMEQ8SEhEPERETFhwXExQaFRERGCEYGh0dHx8fExciJCIeJBweHx7/2wBDAQUFBQcGBw4ICA4eFBEUHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh7/wAARCABAAEADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA/9k=');

  /// يضمن: نسخ النموذجين (أصلي) + تسجيلهما في الحزمة. آمن للاستدعاء المتكرر —
  /// يُستدعى من المحركين (الرئيسي للواجهة والتشخيص، ومحرك guardMain للكشف).
  /// فشل كاشف المناطق لا يُسقط المصنّف — التغطية تعمل كاملةً كاحتياط.
  static Future<bool> ensure() async {
    if (_ready) return true;
    try {
      final prep = await GuardSystem.prepareModel();
      if (prep['ok'] != true) {
        await GuardSystem.logNative('✗ فشل تجهيز النموذج المدمج');
        return false;
      }
      final path = prep['path'] as String;
      await NsfwDetector.instance.registerModel(ModelRegistration(
        id: _modelId,
        displayName: 'غَضّ — نموذج مدمج (بلا شبكة)',
        assetPath: path,
        inputSize: 224,
      ));
      _ready = true;
      await GuardSystem.logNative('النموذج المدمج سُجّل في محرك الكشف — جاهز للفحص');

      // [0.3.0] كاشف المناطق — فشله غير قاتل (الاحتياط: تغطية كاملة).
      if (!_regionsReady && prep['regionsOk'] == true) {
        final rpath = prep['regionsPath'] as String?;
        if (rpath != null && rpath.isNotEmpty) {
          await NsfwDetector.instance.registerModel(ModelRegistration(
            id: _regionsModelId,
            displayName: 'غَضّ — كاشف المناطق (EraX YOLO11n، Apache 2.0)',
            assetPath: rpath,
            inputSize: 640,
            kind: ModelKind.detector,
            classLabels: regionsClassLabels,
          ));
          _regionsReady = true;
          await GuardSystem.logNative('كاشف المناطق سُجّل — تغطية المربعات متاحة');
        }
      }
      return true;
    } catch (e) {
      await GuardSystem.logNative('✗ فشل تسجيل النموذج: $e');
      return false;
    }
  }

  /// [0.3.0] تعيين مناطق المحتوى غير اللائق على إطار JPEG — يعيد مربعات
  /// مُطبَّعة [0..1] (x, y, w, h) منفوخة بهامش 20% (تغطي الصورة كلها لا
  /// الجزء المكشوف وحده، وحارس حدود يمنع الخروج عن الإطار). قائمة فارغة
  /// تعني: المصنّف أعلن غير لائق لكن الكاشف لم يجد مربعات — فالاحتياط
  /// التغطية الكاملة (يُقرر الأصلي).
  static Future<List<List<double>>> detectRegions(Uint8List bytes) async {
    if (!_regionsReady) {
      if (!await ensure()) return const [];
      if (!_regionsReady) return const [];
    }
    try {
      final dynamic result = await NsfwDetector.instance.scanBytes(
        bytes,
        modelId: _regionsModelId,
        confidenceThreshold: 0.25,
      );
      final dets = result.detections;
      if (dets == null || dets.isEmpty) return const [];
      // أعلى 6 مربعات ثقةً — كفى عمليًا، ويحمي من غلال مربعات متدنية.
      final boxes = (dets.toList()
            ..sort((a, b) => b.confidence.compareTo(a.confidence)))
          .take(6)
          .map((d) {
        final bx = d.box;
        final mx = bx.width * 0.20, my = bx.height * 0.20;
        // clamp يعيد num بنيويًا — toDouble() لتثبيت نوع القائمة المُعادة
        final x = (bx.x - mx).clamp(0.0, 1.0).toDouble();
        final y = (bx.y - my).clamp(0.0, 1.0).toDouble();
        final w = (bx.width + 2 * mx).clamp(0.0, 1.0 - x).toDouble();
        final h = (bx.height + 2 * my).clamp(0.0, 1.0 - y).toDouble();
        return <double>[x, y, w, h];
      }).toList();
      await GuardSystem.logNative('تعيين المناطق: ${boxes.length} مربعًا (أعلى ثقة ${dets.first.confidence.toStringAsFixed(2)})');
      return boxes;
    } catch (e) {
      await GuardSystem.logNative('✗ فشل كاشف المناطق: $e');
      return const [];
    }
  }

  /// تسخين النموذج (تحميله في TFLite قبل أول فحص حقيقي) — فحص تجريبي واحد.
  static Future<void> warmUp() async {
    try {
      await NsfwDetector.instance
          .scanBytes(warmupJpeg, modelId: _modelId, confidenceThreshold: 0.7);
      await GuardSystem.logNative('النموذج محمّل ودافئ — أول فحص حقيقي سيكون سريعًا');
    } catch (e) {
      await GuardSystem.logNative('✗ فشل تسخين النموذج: $e');
    }
  }
}

/// المهايئ الوحيد لحزمة nsfw_detect — إن اختلف اسم دالة أو حقل في إصدار مستقبلي
/// من الحزمة فهذا الملف هو موضع التعديل الوحيد (بنية العزل، القسم 4.2 من الوثيقة).
///
/// مسار RAM الكامل (وثيقة الردّ التقني، السؤال 3):
///   Kotlin يرسل JPEG bytes → scanBytes تحللها في الذاكرة → ScanResult يُطبَّع ديناميكيًا.
///   الحزمة تعمل بالكامل على الجهاز (TFLite على أندرويد) بلا تتبع ولا رفع وسائط،
///   والنموذج مدمج داخلها — لا تحميل من الشبكة، وهو أمر مستحيل هنا أصلًا
///   لغياب صلاحية INTERNET عن البيان.
class DetectorService {
  /// تحليل بايتات لقطة (JPEG) في الذاكرة وإرجاع الحكم بمقارنة الثقة بالعتبة.
  ///
  /// النموذج المدمج ثنائي (آمن/غير آمن) مع softmax مدمج في الرسم البياني.
  /// التغطية الموسّعة تخفض العتبة الفعلية إلى 0.45 ليمسك المحتوى غير المحتشم.
  static Future<Map<String, dynamic>> analyzeBytes(
    Uint8List bytes,
    double threshold, {
    bool expanded = false,
  }) async {
    if (!GuardBrain.ready) await GuardBrain.ensure();
    // [تحصين 0.2.3] إن فشل تسجيل النموذج المدمج فلا ننزلق أبدًا إلى scanBytes
    // بلا modelId — كان سقوط النداء على النموذج الافتراضي (opennsfw2_coreml)
    // الذي يحتاج تنزيلًا من الشبكة يُنتج خطأ «ML model not downloaded» المبهم.
    // الآن الخطأ صريح ومباشر ويظهر في سجل الأحداث كما هو.
    if (!GuardBrain.ready) {
      throw PlatformException(
        code: 'MODEL_NOT_READY',
        message: 'النموذج المدمج غير مسجل في محرك الكشف — تحقق من شاشة التشخيص',
      );
    }
    final effective = expanded && threshold > 0.45 ? 0.45 : threshold;
    final dynamic result = await NsfwDetector.instance.scanBytes(
      bytes,
      modelId: GuardBrain.modelId,
      confidenceThreshold: effective,
    );
    final parsed = _bestScore(result);
    // لا نجعل المصنّف الثنائي بوابةً لكاشف المناطق: قد يفوّت صورة صغيرة
    // داخل منشور أو مشهدًا غير صريح. افحص كاشف الأجزاء في كل لقطة وادمج
    // الإشارتين؛ أي مربع حساس موجب يكفي لتفعيل الحماية.
    final regions = await GuardBrain.detectRegions(bytes);
    final unsafe = GuardThreshold.isUnsafeFromSignals(
      parsed.score,
      effective,
      hasSensitiveRegions: regions.isNotEmpty,
    );
    final verdict = <String, dynamic>{
      'unsafe': unsafe,
      'score': parsed.score,
      'label': parsed.label,
      'threshold': effective,
    };
    // عند وجود مربعات، Kotlin يغطي المناطق أو الشاشة كاملة حسب الإعداد.
    // وإن لم ينتج كاشف المناطق مربعات وبقي المصنف إيجابيًا، يستخدم Kotlin
    // التغطية الكاملة الاحتياطية كما كان.
    if (regions.isNotEmpty && GuardSettings.regionMode) {
      verdict['mode'] = 'regions';
      verdict['regions'] = regions;
    }
    return verdict;
  }

  /// استخراج أعلى درجة غير لائقة من نتائج الحزمة — نتجاهل فئات الأمان
  /// (safe/unknown) نعمًا، فالدرجة هي أعلى ثقة في nudity/explicitNudity/suggestive.
  static ({double score, String label}) _bestScore(dynamic result) {
    double best = -1.0;
    String bestLabel = '';
    // الشكل الموثق: ScanResult.labels قائمة NsfwLabel(category, confidence)
    try {
      final labels = result.labels;
      if (labels is List) {
        for (final l in labels) {
          final cat = l.category.toString().split('.').last;
          final conf = (l.confidence as num).toDouble();
          final suspicious =
              cat == 'nudity' || cat == 'explicitNudity' || cat == 'suggestive';
          if (suspicious && conf > best) {
            best = conf;
            bestLabel = cat;
          }
        }
      }
    } catch (_) {}
    if (best >= 0) return (score: best, label: bestLabel);

    // مسارات احتياطية لأشكال أخرى (خريطة، رقم، أو isNsfw الثنائي)
    if (result is num) return (score: result.toDouble(), label: '');
    if (result is Map) {
      for (final key in const ['score', 'nsfwScore', 'confidence', 'porn', 'nsfw', 'explicit']) {
        final v = result[key];
        if (v is num) return (score: v.toDouble(), label: key);
      }
      double deep = 0.0;
      for (final v in result.values) {
        final s = _bestScore(v);
        if (s.score > deep) deep = s.score;
      }
      return (score: deep, label: '');
    }
    try {
      final f = result.isNsfw; // حكم الحزمة الثنائي أخيرًا
      if (f is bool) return (score: f ? 1.0 : 0.0, label: '');
    } catch (_) {}
    return (score: 0.0, label: '');
  }
}
