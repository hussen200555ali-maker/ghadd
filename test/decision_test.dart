import 'package:flutter_test/flutter_test.dart';

import 'package:ghadd/core/decision.dart';

/// عقد سلوك غَضّ (بوابة CI الثالثة — وثيقة الردّ التقني ص13، الخطوة 3).
/// نفس الدلالات ملتزمة بها في GuardPrefs.kt وفي قناة ghadd/analyze.
void main() {
  group('GuardThreshold — العتبات والقوالب', () {
    test('القوالب الثلاث الموثقة', () {
      expect(GuardThreshold.lenient, 0.50);
      expect(GuardThreshold.balanced, 0.70);
      expect(GuardThreshold.strict, 0.85);
      expect(GuardThreshold.presets.length, 3);
    });

    test('الحكم شامل عند التساوي (>=)', () {
      expect(GuardThreshold.isUnsafe(0.85, 0.85), isTrue);
      expect(GuardThreshold.isUnsafe(0.8499, 0.85), isFalse);
      expect(GuardThreshold.isUnsafe(0.86, 0.85), isTrue);
    });

    test('الإسقاط داخل النطاق — لا قيمة خارج 0.50–0.95', () {
      expect(GuardThreshold.clamp(0.1), 0.50);
      expect(GuardThreshold.clamp(1.2), 0.95);
      expect(GuardThreshold.clamp(0.77), 0.77);
      expect(GuardThreshold.clamp(double.nan), GuardThreshold.balanced);
    });

    test('الحكم يستخدم العتبة المُسقطة دائمًا', () {
      // عتبة خارج النطاق تُسقط أولًا — لا يمر حكم بقيمة غير شرعية
      expect(GuardThreshold.isUnsafe(0.52, 0.2), isTrue); // العتبة الفعلية 0.50
      expect(GuardThreshold.isUnsafe(0.49, 0.2), isFalse);
    });

    test('كشف منطقة حساسة يفعّل الحماية حتى لو كان تصنيف الصورة آمنًا', () {
      expect(
        GuardThreshold.isUnsafeFromSignals(
          0.08,
          0.45,
          hasSensitiveRegions: true,
        ),
        isTrue,
      );
      expect(GuardThreshold.isUnsafeFromSignals(0.44, 0.45), isFalse);
      expect(GuardThreshold.isUnsafeFromSignals(0.46, 0.45), isTrue);
    });

    test('قناع الصدر يمتد إلى الجذع وأعلى الفخذين ويبقى داخل الصورة', () {
      final mask = SensitiveBodyMask.expand(
        label: 'NIPPLE',
        x: 0.45,
        y: 0.31,
        width: 0.10,
        height: 0.06,
      );
      expect(mask[0], greaterThanOrEqualTo(0.0));
      expect(mask[1], lessThanOrEqualTo(0.20));
      expect(mask[2], greaterThanOrEqualTo(0.54));
      expect(mask[1] + mask[3], greaterThanOrEqualTo(0.78));
      expect(mask[0] + mask[2], lessThanOrEqualTo(1.0));
    });

    test('قناع الحوض يمتد صعودًا إلى الجذع ويُقص عند حدود الإطار', () {
      final mask = SensitiveBodyMask.expand(
        label: 'PENIS',
        x: 0.91,
        y: 0.86,
        width: 0.08,
        height: 0.08,
      );
      expect(mask[0], greaterThanOrEqualTo(0.0));
      expect(mask[1], lessThanOrEqualTo(0.46));
      expect(mask[0] + mask[2], lessThanOrEqualTo(1.0));
      expect(mask[1] + mask[3], lessThanOrEqualTo(1.0));
    });

    test('أقرب قالب مسبق للمنزلق', () {
      expect(GuardThreshold.nearestPreset(0.72), 'متوازنة');
      expect(GuardThreshold.nearestPreset(0.88), 'صارمة');
      expect(GuardThreshold.nearestPreset(0.51), 'متساهلة');
    });
  });

  group('GuardDecision — قرار التحليل', () {
    test('قرار آمن وتحذيري عند العتبة المتوازنة', () {
      final safe = GuardDecision.fromAnalysis(0.31, 0.7, label: 'safe');
      expect(safe.unsafe, isFalse);
      expect(safe.toMap()['unsafe'], isFalse);

      final bad = GuardDecision.fromAnalysis(0.93, 0.7, label: 'porn');
      expect(bad.unsafe, isTrue);
      expect(bad.toMap()['label'], 'porn');
      expect(bad.toMap()['threshold'], 0.7);
    });
  });

  group('DetectorViewTransform — إحداثيات المناظير [0.3.5]', () {
    test('الترتيب المعلن للمناظير الإضافية', () {
      expect(DetectorViewTransform.extraViews,
          ['mirror', 'rot90', 'rot180', 'rot270']);
    });

    test('rot90 مرتين = rot180، وثلاث مرات = rot270', () {
      final box = <double>[0.1, 0.2, 0.3, 0.4];
      List<double> apply(String t, List<double> b) =>
          DetectorViewTransform.inverseBox(t, b);
      final twice = apply('rot90', apply('rot90', box));
      final r180 = apply('rot180', box);
      final thrice = apply('rot90', twice);
      final r270 = apply('rot270', box);
      for (var i = 0; i < 4; i++) {
        expect(twice[i], closeTo(r180[i], 1e-9));
        expect(thrice[i], closeTo(r270[i], 1e-9));
      }
    });

    test('الإطار الكامل يبقى الإطار الكامل في كل المناظير', () {
      final full = <double>[0.0, 0.0, 1.0, 1.0];
      for (final t in DetectorViewTransform.extraViews) {
        final b = DetectorViewTransform.inverseBox(t, full);
        expect(b[0], closeTo(0.0, 1e-9));
        expect(b[1], closeTo(0.0, 1e-9));
        expect(b[0] + b[2], closeTo(1.0, 1e-9));
        expect(b[1] + b[3], closeTo(1.0, 1e-9));
      }
    });

    test('المرآة تعكس الأفقيات فقط', () {
      final b = DetectorViewTransform.inverseBox('mirror', [0.1, 0.2, 0.3, 0.4]);
      expect(b[0], closeTo(0.6, 1e-9)); // 1 - 0.1 - 0.3
      expect(b[1], closeTo(0.2, 1e-9));
      expect(b[2], closeTo(0.3, 1e-9));
      expect(b[3], closeTo(0.4, 1e-9));
    });

    test('القصّ الآمن: مربع خارج الحدود لا يخرج عنها أبدًا', () {
      final b = DetectorViewTransform.inverseBox('rot90', [0.9, 0.9, 0.5, 0.5]);
      expect(b[0], greaterThanOrEqualTo(0.0));
      expect(b[1], greaterThanOrEqualTo(0.0));
      expect(b[0] + b[2], lessThanOrEqualTo(1.0));
      expect(b[1] + b[3], lessThanOrEqualTo(1.0));
    });
  });

  group('أقنعة NudeNet — المكشوف والمغطّى [0.3.5]', () {
    test('الفئات الحساسة تشمل المغطّى وتستبعد الوجه والأقدام والبطن', () {
      expect(SensitiveBodyMask.sensitiveDetectorLabels
          .contains('FEMALE_BREAST_COVERED'), isTrue);
      expect(SensitiveBodyMask.sensitiveDetectorLabels
          .contains('BUTTOCKS_COVERED'), isTrue);
      expect(SensitiveBodyMask.sensitiveDetectorLabels
          .contains('FEMALE_GENITALIA_COVERED'), isTrue);
      expect(SensitiveBodyMask.sensitiveDetectorLabels
          .contains('ANUS_COVERED'), isTrue);
      expect(SensitiveBodyMask.sensitiveDetectorLabels
          .contains('FACE_FEMALE'), isFalse);
      expect(SensitiveBodyMask.sensitiveDetectorLabels
          .contains('FEET_EXPOSED'), isFalse);
      expect(SensitiveBodyMask.sensitiveDetectorLabels
          .contains('BELLY_EXPOSED'), isFalse);
      expect(SensitiveBodyMask.sensitiveDetectorLabels
          .contains('MALE_BREAST_EXPOSED'), isFalse);
    });

    test('قناع المؤخرة (مغطّاة) يمتد صعودًا نحو الوسط وأعلى الفخذين', () {
      final mask = SensitiveBodyMask.expand(
        label: 'BUTTOCKS_COVERED',
        x: 0.4, y: 0.7, width: 0.2, height: 0.1,
      );
      expect(mask[1], lessThanOrEqualTo(0.5));
      expect(mask[0] + mask[2], lessThanOrEqualTo(1.0));
      expect(mask[1] + mask[3], lessThanOrEqualTo(1.0));
    });

    test('قناع الصدر (مغطّى) يمتد نزولًا إلى الجذع كالصدر المكشوف', () {
      final mask = SensitiveBodyMask.expand(
        label: 'FEMALE_BREAST_COVERED',
        x: 0.45, y: 0.31, width: 0.1, height: 0.06,
      );
      expect(mask[1], lessThanOrEqualTo(0.20));
      expect(mask[1] + mask[3], greaterThanOrEqualTo(0.78));
    });
  });

  group('LocalCounters — عدادات مجردة بلا محتوى', () {
    test('الحجب يزيد اليومي والإجمالي معًا', () {
      final c = LocalCounters();
      c.registerBlock();
      c.registerBlock();
      expect(c.blockedTotal, 2);
      expect(c.blockedToday, 2);
    });

    test('تغيّر اليوم يصفّر اليومي ولا يمس الإجمالي', () {
      final c = LocalCounters()..registerBlock()..registerBlock();
      c.rollDay();
      expect(c.blockedToday, 0);
      expect(c.blockedTotal, 2);
    });

    test('المسارات الرشيقة: محمي ذاتيًا، أخطاء، نتائج متأخرة — كلها محسوبة لا مخفاة', () {
      final c = LocalCounters()
        ..registerProtectedSelf()
        ..registerProtectedSelf()
        ..registerError()
        ..registerLate();
      final stats = c.toStats();
      expect(stats['protected_self'], 2);
      expect(stats['errors'], 1);
      expect(stats['late_results'], 1);
      expect(stats['blocked_total'], 0); // لا حجب — لم تُرَ صورة أصلًا
    });
  });
}
