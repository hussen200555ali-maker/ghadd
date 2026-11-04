/// منطق القرار النقي — النموذج المرجعي الموحّد لسلوك غَضّ (بلا أي اعتماد Flutter).
/// طبقة Flutter وخدمات Kotlin والاختبارات كلها تلتزم بنفس هذه الدلالات،
/// واختبارات unit في test/ تثبّتها كعقد (بوابة CI الثالثة).
library;

/// عتبات الكشف: ثلاث قوالب مسبقة + نطاق المنزلق الدقيق.
class GuardThreshold {
  GuardThreshold._();

  /// القوالب الثلاث الموثقة (القسم 4.2 من دراسة الجدوى وصفحة 10 من وثيقة الردّ).
  static const double lenient = 0.50; // متساهلة
  static const double balanced = 0.70; // متوازنة — الافتراضي
  static const double strict = 0.85; // صارمة

  static const Map<String, double> presets = {
    'متساهلة': lenient,
    'متوازنة': balanced,
    'صارمة': strict,
  };

  /// أدنى وأقصى قيمة للمنزلق اليدوي.
  static const double min = 0.50;
  static const double max = 0.95;

  /// إسقاط أي قيمة داخل النطاق المسموح (المستخدم لا يصل لنطاق خاطئ أبدًا).
  static double clamp(double value) {
    if (value.isNaN) return balanced;
    final v = value < min ? min : value;
    return v > max ? max : v;
  }

  /// أقرب قالب مسبق لقيمة اختيارها المستخدم من المنزلق (لإبراز الشريحة النشطة).
  static String nearestPreset(double value) {
    var best = presets.keys.first;
    var bestDist = double.infinity;
    presets.forEach((name, t) {
      final d = (value - t).abs();
      if (d < bestDist) {
        bestDist = d;
        best = name;
      }
    });
    return best;
  }

  /// الحكم: الدرجة تبلغ العتبة أو تجاوزتها (>= — حد شامل عند التساوي).
  static bool isUnsafe(double score, double threshold) {
    final t = clamp(threshold);
    return score >= t;
  }

  /// يكفي كشف منطقة حساسة للحجب حتى إن أخفق مصنّف الصورة الكاملة.
  /// لا نُسقط العتبة هنا لأن الوضع الموسّع يستخدم 0.45 عمدًا.
  static bool isUnsafeFromSignals(
    double score,
    double effectiveThreshold, {
    bool hasSensitiveRegions = false,
  }) =>
      hasSensitiveRegions || score >= effectiveThreshold;
}

/// يوسّع كشف نقطة حساسة إلى نطاق الجذع وأعلى الفخذين بدل مربع صغير حولها.
/// هذه تغطية هندسية محافظة وليست تجزئة دقيقة لشكل الجسم.
class SensitiveBodyMask {
  SensitiveBodyMask._();

  static List<double> expand({
    required String label,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    final normalized = label.trim().toUpperCase();
    final centerX = x + width / 2;
    final centerY = y + height / 2;
    final upperBody = const {
      'NIPPLE', 'FEMALE_BREAST_EXPOSED', 'MALE_BREAST_EXPOSED',
      'BELLY_EXPOSED', 'ARMPITS_EXPOSED', 'BACK_EXPOSED', 'TORSO_EXPOSED',
    }.contains(normalized);
    final lowerBody = const {
      'ANUS', 'PENIS', 'VAGINA', 'ANUS_EXPOSED',
      'MALE_GENITALIA_EXPOSED', 'FEMALE_GENITALIA_EXPOSED',
      'BUTTOCKS_EXPOSED', 'THIGH_EXPOSED',
    }.contains(normalized);

    final minWidth = normalized == 'MAKE_LOVE' ? 0.72 : 0.54;
    final targetWidth = (width * 3.5 > minWidth ? width * 3.5 : minWidth)
        .clamp(0.0, 1.0)
        .toDouble();
    final left = (centerX - targetWidth / 2).clamp(0.0, 1.0).toDouble();
    final right = (centerX + targetWidth / 2).clamp(0.0, 1.0).toDouble();

    final topReach = upperBody
        ? (height * 2 > 0.16 ? height * 2 : 0.16)
        : lowerBody
            ? (height * 5.5 > 0.45 ? height * 5.5 : 0.45)
            : (height * 4 > 0.34 ? height * 4 : 0.34);
    final bottomReach = upperBody
        ? (height * 5.5 > 0.45 ? height * 5.5 : 0.45)
        : lowerBody
            ? (height * 2 > 0.18 ? height * 2 : 0.18)
            : (height * 4 > 0.38 ? height * 4 : 0.38);
    final top = (centerY - topReach).clamp(0.0, 1.0).toDouble();
    final bottom = (centerY + bottomReach).clamp(0.0, 1.0).toDouble();

    return <double>[left, top, right - left, bottom - top];
  }
}

/// قرار مكتمل من تحليل واحد — نفس شكل ردّ قناة ghadd/analyze.
class GuardDecision {
  const GuardDecision({
    required this.unsafe,
    required this.score,
    required this.threshold,
    this.label = '',
  });

  final bool unsafe;
  final double score;
  final double threshold;
  final String label;

  factory GuardDecision.fromAnalysis(double score, double threshold, {String label = ''}) {
    final t = GuardThreshold.clamp(threshold);
    return GuardDecision(
      unsafe: score >= t,
      score: score,
      threshold: t,
      label: label,
    );
  }

  Map<String, dynamic> toMap() => {
        'unsafe': unsafe,
        'score': score,
        'threshold': threshold,
        'label': label,
      };
}

/// العدادات المحلية — أرقام مجردة فقط، لا صور ولا نصوص (صفحة 9 من وثيقة الردّ).
/// هذا هو النموذج المرجعي؛ المرآة الفعلية في GuardPrefs.kt بنفس الدلالات.
class LocalCounters {
  int blockedTotal = 0;
  int blockedToday = 0;
  int protectedSelf = 0; // محتوى رفضه النظام الالتقاط (FLAG_SECURE)
  int errors = 0; // أخطاء تحليل/عرض محسوبة لا مخفاة
  int lateResults = 0; // نتائج تجاوزت مهلة 5 ثوانٍ أو سبقها حدث أحدث

  void registerBlock() {
    blockedTotal += 1;
    blockedToday += 1;
  }

  void registerProtectedSelf() => protectedSelf += 1;
  void registerError() => errors += 1;
  void registerLate() => lateResults += 1;

  /// تصفير اليوم فقط عند تغيّر التاريخ (يبقى الإجمالي تراكميًا).
  void rollDay() => blockedToday = 0;

  Map<String, dynamic> toStats() => {
        'blocked_total': blockedTotal,
        'blocked_today': blockedToday,
        'protected_self': protectedSelf,
        'errors': errors,
        'late_results': lateResults,
      };
}
