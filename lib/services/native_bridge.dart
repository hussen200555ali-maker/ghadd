import 'dart:typed_data';

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

  static const _channel = MethodChannel('ghadd/control');

  /// استعادة الحالة من التفضيلات المحلية عند الإقلاع (قبل أي عرض للواجهة).
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    consent = p.getBool('ghadd_consent') ?? false;
    enabled = p.getBool('ghadd_enabled') ?? false;
    threshold = p.getDouble('ghadd_threshold') ?? 0.7;
    whitelist = p.getStringList('ghadd_whitelist') ?? const [];
  }

  /// يدفع الإعدادات كاملة إلى المرآتين (محلية + أصلية) بعد أي تعديل.
  static Future<void> sync() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('ghadd_consent', consent);
    await p.setBool('ghadd_enabled', enabled);
    await p.setDouble('ghadd_threshold', threshold);
    await p.setStringList('ghadd_whitelist', whitelist);
    try {
      await _channel.invokeMethod('sync', {
        'consent': consent,
        'enabled': enabled,
        'threshold': threshold,
        'whitelist': whitelist,
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
    try { await _channel.invokeMethod('startGuard'); } on PlatformException {}
  }

  static Future<void> stopGuard() async {
    try { await _channel.invokeMethod('stopGuard'); } on PlatformException {}
  }

  static Future<void> openAccessibilitySettings() async {
    try { await _channel.invokeMethod('openAccessibilitySettings'); } on PlatformException {}
  }

  static Future<void> openOverlaySettings() async {
    try { await _channel.invokeMethod('openOverlaySettings'); } on PlatformException {}
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
        return DetectorService.analyzeBytes(bytes, threshold);
      }
      throw MissingPluginException();
    });
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
  static Future<Map<String, dynamic>> analyzeBytes(Uint8List bytes, double threshold) async {
    final dynamic result = await NsfwDetector.instance.scanBytes(bytes);
    final score = _bestScore(result);
    final label = _bestLabel(result);
    return {
      'unsafe': score >= threshold,
      'score': score,
      'label': label,
    };
  }

  /// استخراج أعلى درجة NSFW من أشكال النتائج المحتملة
  /// (ScanResult كائن، خريطة تصنيفات labels، قائمة كشفات بصناديق، أو رقم).
  static double _bestScore(dynamic result) {
    if (result is num) return result.toDouble();
    if (result is Map) {
      for (final key in const ['score', 'nsfwScore', 'confidence', 'porn', 'nsfw', 'explicit']) {
        final v = result[key];
        if (v is num) return v.toDouble();
      }
      double best = 0.0;
      for (final v in result.values) {
        final s = _bestScore(v);
        if (s > best) best = s;
      }
      return best;
    }
    if (result is List) {
      double best = 0.0;
      for (final v in result) {
        final s = _bestScore(v);
        if (s > best) best = s;
      }
      return best;
    }
    // كائنات الحزمة: نجرب الحقول الشائعة عبر استدعاءات ديناميكية آمنة
    try {
      final s = result.score;
      if (s is num) return s.toDouble();
    } catch (_) {}
    try {
      final s = result.nsfwScore;
      if (s is num) return s.toDouble();
    } catch (_) {}
    try {
      final l = result.labels; // خريطة تصنيف → درجة (شكل ScanResult الموثق)
      if (l is Map) return _bestScore(l);
    } catch (_) {}
    try {
      final l = result.detections;
      if (l is List && l.isNotEmpty) return _bestScore(l);
    } catch (_) {}
    try {
      final f = result.isNsfw; // مسار مختصر: حكم ثنائي بلا درجة ظاهرة
      if (f is bool) return f ? 1.0 : 0.0;
    } catch (_) {}
    return 0.0;
  }

  static String _bestLabel(dynamic result) {
    if (result is Map) {
      for (final key in const ['label', 'category', 'topCategory', 'name']) {
        final v = result[key];
        if (v != null) return v.toString();
      }
    }
    try {
      final l = result.label;
      if (l != null) return l.toString();
    } catch (_) {}
    try {
      final c = result.topCategory;
      if (c != null) return c.toString();
    } catch (_) {}
    try {
      final m = result.labels;
      if (m is Map && m.isNotEmpty) {
        // التصنيف الأعلى درجة في خريطة labels
        String bestKey = '';
        double bestVal = -1.0;
        m.forEach((k, v) {
          if (v is num && v.toDouble() > bestVal) {
            bestVal = v.toDouble();
            bestKey = k.toString();
          }
        });
        if (bestKey.isNotEmpty) return bestKey;
      }
    } catch (_) {}
    return '';
  }
}
