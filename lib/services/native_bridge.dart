import 'dart:convert';
import 'dart:ui' as ui;

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
/// [0.3.5] كاشف المناطق: NudeNet v3.4 YOLOv8n (AGPL-3.0، 18 فئة) — مربعات
/// لأجزاء الجسم المكشوفة والمغطّاة بإحداثيات مُطبَّعة، مُحوَّل TFLite
/// (onnx2tf) ومتحقق رقميًا (أقصى فرق 0.0006 مقابل مرجع PyTorch عبر أربع
/// مدخلات). يُستخدم لتعيين مواضع المحتوى في كل لقطة — لتغطية المناطق فقط
/// بدل الشاشة كاملة — مع مسح متعدد المناظير وتكبير رباعي للوضعيات الصعبة.
class GuardBrain {
  GuardBrain._();

  static const _modelId = 'ghadd_nsfw';
  static const _regionsModelId = 'ghadd_nsfw_regions';

  /// [0.3.5] جدول فئات NudeNet v3.4 الثماني عشرة — الترتيب عقد صامت مع ملف
  /// النموذج (YOLOv8n المدرّب على NudeNet، TFLite float32، بدخل 640): يجب
  /// أن يطابق حرفيًا ترتيب names أثناء التحويل وجدول NUDENET_LABELS في
  /// TFLiteDetectorEngine — تغييره بلا إعادة تحويل يقلب الفئات.
  static const regionsClassLabels = <String>[
    'FEMALE_GENITALIA_COVERED', 'FACE_FEMALE', 'BUTTOCKS_EXPOSED',
    'FEMALE_BREAST_EXPOSED', 'FEMALE_GENITALIA_EXPOSED', 'MALE_BREAST_EXPOSED',
    'ANUS_EXPOSED', 'FEET_EXPOSED', 'BELLY_COVERED', 'FEET_COVERED',
    'ARMPITS_COVERED', 'ARMPITS_EXPOSED', 'FACE_MALE', 'BELLY_EXPOSED',
    'MALE_GENITALIA_EXPOSED', 'ANUS_COVERED', 'FEMALE_BREAST_COVERED',
    'BUTTOCKS_COVERED',
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

      // [0.3.5] كاشف المناطق NudeNet v3.4 (18 فئة) — فشله غير قاتل
      // (الاحتياط: تغطية كاملة).
      if (!_regionsReady && prep['regionsOk'] == true) {
        final rpath = prep['regionsPath'] as String?;
        if (rpath != null && rpath.isNotEmpty) {
          await NsfwDetector.instance.registerModel(ModelRegistration(
            id: _regionsModelId,
            displayName: 'غَضّ — كاشف المناطق (NudeNet v3.4 YOLOv8n، 18 فئة، AGPL-3.0)',
            assetPath: rpath,
            inputSize: 640,
            kind: ModelKind.detector,
            classLabels: regionsClassLabels,
          ));
          _regionsReady = true;
          await GuardSystem.logNative('كاشف المناطق NudeNet (18 فئة) سُجّل — تغطية موضعية موسّعة');
        }
      }
      return true;
    } catch (e) {
      await GuardSystem.logNative('✗ فشل تسجيل النموذج: $e');
      return false;
    }
  }

  /// تعيين مناطق المحتوى غير اللائق على إطار JPEG — يعيد أقنعة واسعة
  /// مُطبَّعة [0..1] (x, y, w, h) من موضع الكشف إلى الجذع وأعلى الفخذين.
  /// قائمة فارغة مع إنذار المصنف تعني استخدام التغطية الكاملة الاحتياطية.
  ///
  /// [0.3.5] المسح العميق — ثلاث مراحل بإنهاء مبكر (علاج «لا يكشف جميع
  /// المناطق مع اختلاف الوضعيات»):
  ///   1) الإطار الكامل كما هو — اللقطة القياسية.
  ///   2) المناظير الأربعة (مرآة/90°/180°/270°) — الوضعيات المدوّرة
  ///      والمقلوبة والمصوَّرة بالعرض؛ كل مربع يعاد إلى إحداثيات الإطار
  ///      الأصلي بدالة نقية (DetectorViewTransform) قبل التوسيع.
  ///   3) التكبير الرباعي — أربع قصّات 62.5% متراكبة 25%؛ المناطق الصغيرة
  ///      (مصغّرات، نوافذ مدمجة) تملأ إدخال الكاشف فترتفع ثقتها.
  /// deep=false يقصر المسح على المرحلة 1 (يُستخدم حين يكون المصنّف قد
  /// أعلن عدم اللائق فعلًا — المربعات حينها لتحسين التغطية فقط).
  static Future<List<List<double>>> detectRegions(
    Uint8List bytes, {
    bool deep = true,
  }) async {
    if (!_regionsReady) {
      if (!await ensure()) return const [];
      if (!_regionsReady) return const [];
    }
    try {
      // المرحلة 1: الإطار الكامل
      final direct = _expandDets(await _rawSensitive(bytes));
      if (direct.isNotEmpty) return direct;
      if (!deep) return const [];

      // المرحلة 2 و3 تشاركان فكًّا واحدًا للإطار — بإنهاء مبكر عند أول إصابة
      final frame = await _decodeFrame(bytes);
      if (frame != null) {
        try {
          // المرحلة 2: المناظير — الوضعيات المدوّرة والمقلوبة
          for (final view in DetectorViewTransform.extraViews) {
            final dets = await _rawSensitiveOnView(frame, view);
            if (dets.isEmpty) continue;
            final boxes = <List<double>>[];
            for (final d in dets) {
              final bx = d.box as dynamic;
              final original = DetectorViewTransform.inverseBox(view, <double>[
                bx.x as double, bx.y as double, bx.width as double, bx.height as double,
              ]);
              boxes.add(SensitiveBodyMask.expand(
                label: (d.label as dynamic).toString(),
                x: original[0], y: original[1],
                width: original[2], height: original[3],
              ));
            }
            final valid = _validMasks(boxes);
            if (valid.isNotEmpty) {
              await GuardSystem.logNative('مناطق عبر منظير $view — ${valid.length} مربعًا');
              return valid;
            }
          }

          // المرحلة 3: التكبير الرباعي — المناطق الصغيرة
          final quads = await _rawSensitiveOnQuadrants(frame);
          if (quads.isNotEmpty) {
            await GuardSystem.logNative('مناطق عبر التكبير الرباعي — ${quads.length} مربعًا');
          }
          return quads;
        } finally {
          frame.dispose();
        }
      }
      return const [];
    } catch (e) {
      await GuardSystem.logNative('✗ فشل كاشف المناطق: $e');
      return const [];
    }
  }

  /// كشف خام على بايتات جاهزة، مع فلتر الفئات الحساسة حصرًا (الوجوه
  /// والأقدام والبطن والإبط وصدر الرجل خارج نطاق الحجب المتفق عليه).
  static Future<List<dynamic>> _rawSensitive(Uint8List bytes) async {
    final dynamic result = await NsfwDetector.instance.scanBytes(
      bytes,
      modelId: _regionsModelId,
      confidenceThreshold: 0.15,
    );
    final dets = result.detections as List<dynamic>?;
    if (dets == null || dets.isEmpty) return const [];
    return dets
        .where((d) => SensitiveBodyMask.sensitiveDetectorLabels
            .contains((d.label as dynamic).toString().trim().toUpperCase()))
        .toList(growable: false);
  }

  /// توسيع الكشوفات الحساسة إلى أقنعة — حتى 12 مربعًا بترتيب الثقة تنازليًا
  /// (العتبة 0.15 منخفضة عمدًا: الإيجابية الكاذبة أهدأ من التفويت).
  static List<List<double>> _expandDets(List<dynamic> dets) {
    if (dets.isEmpty) return const [];
    final sorted = dets.toList()
      ..sort((a, b) => (b.confidence as double).compareTo(a.confidence as double));
    final masks = <List<double>>[];
    for (final d in sorted.take(12)) {
      final bx = d.box as dynamic;
      masks.add(SensitiveBodyMask.expand(
        label: (d.label as dynamic).toString(),
        x: bx.x as double, y: bx.y as double,
        width: bx.width as double, height: bx.height as double,
      ));
    }
    return _validMasks(masks);
  }

  /// حصالة الأقنعة: استبعاد المربعات المقلوبة أو النحيلة بعد القصّ.
  static List<List<double>> _validMasks(List<List<double>> masks) =>
      masks.where((m) => m[2] > 0.01 && m[3] > 0.01).toList(growable: false);

  /// فك إطار JPEG مرة واحدة وإعادة استخدامه في كل المناظير والقصّات.
  static Future<ui.Image?> _decodeFrame(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = (await codec.getNextFrame()).image;
      codec.dispose();
      return frame;
    } catch (_) {
      return null;
    }
  }

  /// إنتاج بايتات PNG لمنظير مُدار/معكوس من الإطار مصغّرًا إلى حد أقصى
  /// 640 لجهة الكاشف — التطبيع [0..1] يبقى صحيحًا مهما كان التصغير.
  static Future<Uint8List?> _viewBytes(ui.Image frame, String view) async {
    try {
      final srcW = frame.width;
      final srcH = frame.height;
      final swap = view == 'rot90' || view == 'rot270';
      final outW = swap ? srcH : srcW;
      final outH = swap ? srcW : srcH;
      final scale = 640.0 / (outW > outH ? outW : outH);
      final dstW = (outW * scale).round().clamp(1, 640);
      final dstH = (outH * scale).round().clamp(1, 640);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder,
          ui.Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()));
      canvas.scale(scale);
      switch (DetectorViewTransform.normalize(view)) {
        case 'rot90': // مع عقارب الساعة
          canvas.translate(outW.toDouble(), 0);
          canvas.rotate(3.1415926535897932 / 2);
          break;
        case 'rot180':
          canvas.translate(outW.toDouble(), outH.toDouble());
          canvas.rotate(3.1415926535897932);
          break;
        case 'rot270': // عكس عقارب الساعة
          canvas.translate(0, outH.toDouble());
          canvas.rotate(-3.1415926535897932 / 2);
          break;
        default: // mirror
          canvas.translate(outW.toDouble(), 0);
          canvas.scale(-1.0, 1.0);
      }
      canvas.drawImage(frame, ui.Offset.zero, ui.Paint());
      final picture = recorder.endRecording();
      final img = await picture.toImage(dstW, dstH);
      picture.dispose();
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// كشف على منظير مُدار ثم إعادة مربعاته الخام إلى إحداثيات الإطار الأصلي.
  static Future<List<dynamic>> _rawSensitiveOnView(
      ui.Image frame, String view) async {
    final vb = await _viewBytes(frame, view);
    if (vb == null) return const [];
    return _rawSensitive(vb);
  }

  /// التكبير الرباعي: أربع قصّات 62.5% متراكبة 25% من الإطار الأصلي، كل
  /// قصّة تُمرَّر للكاشف بمحافظة على نسبتها (بلا تشويه) والمربعات تعود
  /// إلى إحداثيات الإطار الكامل قبل التوسيع.
  static Future<List<List<double>>> _rawSensitiveOnQuadrants(
      ui.Image frame) async {
    const windows = <List<double>>[
      [0.0, 0.0, 0.625, 0.625],
      [0.375, 0.0, 0.625, 0.625],
      [0.0, 0.375, 0.625, 0.625],
      [0.375, 0.375, 0.625, 0.625],
    ];
    final srcW = frame.width.toDouble();
    final srcH = frame.height.toDouble();
    try {
      for (final win in windows) {
        final cx = win[0], cy = win[1], cw = win[2], ch = win[3];
        final cropW = (srcW * cw).round().clamp(1, frame.width);
        final cropH = (srcH * ch).round().clamp(1, frame.height);
        final sx = (srcW * cx).round();
        final sy = (srcH * cy).round();
        // الحفاظ على النسبة: الوجه الأكبر 640 والآخر بالتناسب
        final scale = 640.0 / (cropW > cropH ? cropW : cropH);
        final dstW = (cropW * scale).round().clamp(1, 640);
        final dstH = (cropH * scale).round().clamp(1, 640);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder,
            ui.Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()));
        canvas.drawImageRect(
          frame,
          ui.Rect.fromLTWH(sx.toDouble(), sy.toDouble(),
              cropW.toDouble(), cropH.toDouble()),
          ui.Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()),
          ui.Paint(),
        );
        final picture = recorder.endRecording();
        final img = await picture.toImage(dstW, dstH);
        picture.dispose();
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        if (data == null) continue;
        final dets = await _rawSensitive(data.buffer.asUint8List());
        if (dets.isEmpty) continue;
        final masks = <List<double>>[];
        for (final d in dets) {
          final bx = d.box as dynamic;
          // من إحداثيات القصّة المُطبَّعة إلى إحداثيات الإطار الكامل
          final fx = cx + (bx.x as double) * cw;
          final fy = cy + (bx.y as double) * ch;
          final fw = (bx.width as double) * cw;
          final fh = (bx.height as double) * ch;
          masks.add(SensitiveBodyMask.expand(
            label: (d.label as dynamic).toString(),
            x: fx, y: fy, width: fw, height: fh,
          ));
        }
        final valid = _validMasks(masks);
        if (valid.isNotEmpty) return valid; // إنهاء مبكر عند أول قصّة مثمرة
      }
      return const [];
    } catch (_) {
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
    // [0.3.5] المسح العميق (مناظير + تكبير رباعي) يعمل حين يصمت المصنّف —
    // صمام الأمان للوضعيات الصعبة؛ وحين ينذر المصنّف يكفي مسح الإطار
    // الكامل السريع (المربعات حينها لتحسين التغطية الموضعية فقط).
    final classifierUnsafe = parsed.score >= effective;
    final regions =
        await GuardBrain.detectRegions(bytes, deep: !classifierUnsafe);
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
