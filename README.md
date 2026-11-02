# غَضّ — تطبيق أندرويد للحماية البصرية الطوعية

**حماية بصرية طوعية بلا صلاحية إنترنت: كشف محلي بالكامل، دائم التشغيل، وشفافية قابلة للفحص.**

> غَضّ يلتقط لقطة الشاشة عند تغيّر محتواها، يحللها **على الجهاز بالكامل** بنموذج مدمج،
> ويغطي الشاشة إذا كان المحتوى غير لائق. لا يملك صلاحية `INTERNET` إطلاقًا —
> لا يستطيع إرسال أي بايت خارج جهازك ولو أراد، ويمكنك إثبات ذلك بأمر واحد.

---

## الوعود الثلاثة (الميثاق التأسيسي)

| # | الوعد | كيف يُثبت |
|---|-------|-----------|
| 1 | **بلا إنترنت** — صفر صلاحيات شبكة | `aapt2 dump badging` + بوابة CI ترفض البناء إن ظهرت `INTERNET` |
| 2 | **اللقطة لا تلمس القرص** — ذاكرة متطايرة فقط | مسار RAM في `GuardAccessibilityService` (JPEG في الذاكرة → `scanBytes`) |
| 3 | **طوعية صريحة** — موافقة إفصاح بارز قبل أي شيء | شاشة `DisclosureScreen` + `GuardPrefs.canGuard = consent && enabled` |

## البنية (ملخص وثيقة الردّ التقني)

- **Flutter**: الشاشات (الإفصاح، الرئيسية، الإعدادات) + محرك الكشف `nsfw_detect` في محرك خلفي.
- **Kotlin**: `GuardAccessibilityService` (debounce 400ms + takeScreenshot أو مسار بديل) · `GuardForegroundService` (START_STICKY) · `ProjectionCaptureEngine` + `ProjectionService` (مسار أندرويد 9/10) · `OverlayController` · `GuardPrefs`.
- **القنوات**: `ghadd/control` (إعدادات وموافقة) · `ghadd/system` (تشغيل/إيقاف ومنح) · `ghadd/analyze` (بايتات اللقطة → قرار).
- **قاعدة الذيل الأخير**: قرار الحجب يُنفَّذ في Kotlin — الحماية قائمة حتى لو قُتلت واجهة Flutter.

## الإصدارات المدعومة

| إصدار أندرويد | مسار الالتقاط | ملاحظات |
|---|---|---|
| 11+ (API 30+) | `takeScreenshot` الرسمي لخدمة الوصول | المسار الأساسي |
| 9 و10 (API 28/29) | تصريح عرض الشاشة (MediaProjection) | حوار النظام نفسه — الإطارات في الذاكرة فقط، ويُعاد تأكيده بعد كل إقلاع |

## التشغيل محليًا

```bash
# 1) استكمال ملفات المنصة الناقصة (لا يلمس الملفات المخصصة)
flutter create --platforms=android --org app.ghadd --project-name ghadd .

# 2) الاعتمادات ثم التشغيل
flutter pub get
flutter run

# 3) اختبارات عقد السلوك
flutter test
```

## افحص وعد «بلا إنترنت» بنفسك

```bash
flutter build apk --release
# ملاحظة: بناء --debug يضيف INTERNET تلقائيًا من أدوات Flutter — افحص الإصدار حصرًا
aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk | grep uses-permission
# المتوقع: 7 صلاحيات (5 معلنة + 2 نظاميتان من سلسلة البناء) — ولا شبكية بينها:
#   SYSTEM_ALERT_WINDOW · FOREGROUND_SERVICE · FOREGROUND_SERVICE_SPECIAL_USE
#   POST_NOTIFICATIONS · RECEIVE_BOOT_COMPLETED · WAKE_LOCK · DYNAMIC_RECEIVER_*
# التفصيل الكامل في PRIVACY.md
```

## بوابات CI الثلاث (تعمل تلقائيًا على كل PR ودفع)

1. **الجودة**: `flutter analyze` + `flutter test` (عقد العتبات والعدادات).
2. **رفض الإنترنت**: بناء `--release` ثم `aapt2` — فشل فوري عند أي `INTERNET/ACCESS_NETWORK_STATE`، وتطابق حرفي مع القائمة البيضاء الموثقة (5 معلنة + 2 نظاميتان).
3. انظر `.github/workflows/ci.yml` — كل انحراف عن الميثاق يكسر البناء، لا يتسامح معه.

## هيكل المستودع

```
lib/
  app.dart                      # الهوية + بوابة الإقلاع (الإفصاح أولًا)
  core/decision.dart            # منطق القرار النقي (العتبات، العدادات) — عقد الاختبارات
  screens/disclosure_screen.dart# الإفصاح البارز (مخطط الواجهة 1)
  screens/home_screen.dart      # المعالج + المفتاح + العدادات
  screens/settings_screen.dart  # العتبة + القائمة البيضاء
  services/native_bridge.dart   # المهايئ الوحيد لـnsfw_detect (scanBytes في RAM)
android/.../app/ghadd/guard/
  GuardAccessibilityService.kt  # الالتقاط + مسار RAM + التوليد/المهلة
  GuardForegroundService.kt     # الإشعار الدائم + START_STICKY
  OverlayController.kt          # طبقة الحجب
  GuardPrefs.kt                 # مرآة الإعدادات + بوابة الموافقة
.github/workflows/ci.yml        # البوابات الثلاث
docs/                           # PR-1 · MILESTONES · RELEASE-CHECKLIST · PUSH
PRIVACY.md                      # وثيقة الصلاحيات المعلنة والنظاميات والوعود
```

## التوثيق المرافق

- **دراسة الجدوى التأسيسية** (28 صفحة) — خارج هذا المستودع، مرجع الأرقام والمخاطر.
- **وثيقة الردّ التقني ومخططات الواجهات** (13 صفحة) — أسئلة البنية الخمسة + الويرفريمات.
- `PRIVACY.md` — الصلاحيات المعلنة والنظاميات وسبب كل واحدة، بالجملة القابلة للاقتباس.
- `docs/MILESTONES.md` — حزم الأسابيع الثمانية أ1–أ8 وبوابات إنجازها.

## خارطة الإصدارات

- `v0.1.0-alpha` (المرحلة الحالية): إثبات الفكرة — الإفصاح + مسار RAM + الحجب + البوابات.
- الخطوة التالية: حزم أ5–أ8 (البقاء على أجهزة OEM، التدقيق، الإطلاق) وفق `docs/MILESTONES.md`.

## الترخيص

MIT — انظر [LICENSE](LICENSE). الاستخدام شخصي أصلًا؛ أي توزيع علني يمر أولًا ببوابات الإفصاح الموثقة في دراسة الجدوى.
