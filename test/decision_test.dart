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
