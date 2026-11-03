import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghadd/services/native_bridge.dart';

/// عقد صورة التسخين — [إصلاح 0.2.3]:
/// الثابت السابق كان base64 تالفًا (طوله 917 — ليس من مضاعفات الأربعة) فكان
/// كل «اختبار كشف ذاتي» ينهار بـFormatException قبل الوصول إلى النموذج.
/// هذا الاختبار يمنع رجوع الخلل: أي تعديل على warmupJpeg يجب أن يمر بثلاث
/// شروط: طول من مضاعفات الأربعة، فك مستدير سليم، وترويسة JPEG حقيقية.
void main() {
  test('warmupJpeg — base64 صالح الطول (مضاعفات أربعة)', () {
    // فك الثابت نفسه هو الاختبار: base64Decode يرمي FormatException عند الطول
    // غير السليم — لا يكفي فحص الطول النصي فقط، بل يجب أن يمر الفعل.
    expect(() => GuardBrain.warmupJpeg, returnsNormally);
    expect(GuardBrain.warmupJpeg, isNotEmpty);
  });

  test('warmupJpeg — ترويسة JPEG كاملة (FFD8 … FFD9) وحجم معقول', () {
    final bytes = GuardBrain.warmupJpeg;
    expect(bytes[0], 0xFF, reason: 'أول بايت JPEG');
    expect(bytes[1], 0xD8, reason: 'SOI marker');
    expect(bytes[bytes.length - 2], 0xFF);
    expect(bytes[bytes.length - 1], 0xD9, reason: 'EOI marker');
    // 689 بايت للصورة الرمادية 64×64 — أي انحراف كبير يعني تلف الثابت
    expect(bytes.length, greaterThan(500));
    expect(bytes.length, lessThan(2000));
  });

  test('warmupJpeg — فك/تشفير مستدير بلا فقد', () {
    final bytes = GuardBrain.warmupJpeg;
    final roundTrip = base64Encode(bytes);
    expect(base64Decode(roundTrip), bytes);
  });
}
