import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nsfw_detect/nsfw_detect.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const _channel = MethodChannel('ghadd/control');

  /// استعادة الحالة من التفضيلات المحلية عند الإقلاع (قبل أي عرض للواجهة).
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    consent = p.getBool('ghadd_consent') ?? false;
    enabled = p.getBool('ghadd_enabled') ?? false;
    threshold = p.getDouble('ghadd_threshold') ?? 0.7;
    whitelist = p.getStringList('ghadd_whitelist') ?? const [];
    expandedCoverage = p.getBool('ghadd_expanded') ?? true;
  }

  /// يدفع الإعدادات كاملة إلى المرآتين (محلية + أصلية) بعد أي تعديل.
  static Future<void> sync() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('ghadd_consent', consent);
    await p.setBool('ghadd_enabled', enabled);
    await p.setDouble('ghadd_threshold', threshold);
    await p.setStringList('ghadd_whitelist', whitelist);
    await p.setBool('ghadd_expanded', expandedCoverage);
    try {
      await _channel.invokeMethod('sync', {
        'consent': consent,
        'enabled': enabled,
        'threshold': threshold,
        'whitelist': whitelist,
        'expanded': expandedCoverage,
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

/// عقل الكشف: يضمن وجود النموذج المدمج ومسجلاً في الحزمة قبل أي فحص.
/// النموذج داخل أصول الـAPK (88MB) — يُنسخ مرة واحدة إلى ملفات التطبيق ثم
/// يُسجل عبر registerModel. لا شبكة إطلاقًا — هذا هو الإصلاح الجذري لصمت الكشف.
class GuardBrain {
  GuardBrain._();

  static const _modelId = 'ghadd_nsfw';
  static bool _ready = false;

  static String get modelId => _modelId;
  static bool get ready => _ready;

  /// صورة اختبار 64×64 رمادية (JPEG مبني في الذاكرة) — للتسخين والفحص الذاتي.
  static final Uint8List warmupJpeg =
      base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAoHBwgHBgoICAgLCgoLDhgQDg0NDh0VFhEYIx8lJCIfIiEmKzcvJik0KSEiMEExNDk7Pj4+JS5ESUM8SDc9Pjv/2wBDAQoLCw4NDhwQEBw7KCIoOzs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozv/wAARCABAAEADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwCGiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigD//Z');

  /// يضمن: نسخ النموذج (أصلي) + تسجيله في الحزمة. آمن للاستدعاء المتكرر —
  /// يُستدعى من المحركين (الرئيسي للواجهة والتشخيص، ومحرك guardMain للكشف).
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
      return true;
    } catch (e) {
      await GuardSystem.logNative('✗ فشل تسجيل النموذج: $e');
      return false;
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
    final effective = expanded && threshold > 0.45 ? 0.45 : threshold;
    final dynamic result = await NsfwDetector.instance.scanBytes(
      bytes,
      modelId: GuardBrain.ready ? GuardBrain.modelId : null,
      confidenceThreshold: effective,
    );
    final parsed = _bestScore(result);
    return {
      'unsafe': parsed.score >= effective,
      'score': parsed.score,
      'label': parsed.label,
      'threshold': effective,
    };
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
