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
- **Kotlin**: `GuardAccessibilityService` (debounce 400ms + takeScreenshot أو مسار بديل + النقر الآلي المقيّد لحوار الاسترداد) · `GuardForegroundService` (START_STICKY) · `ProjectionCaptureEngine` + `ProjectionService` (مسار أندرويد 9/10 — START_STICKY + إنقاذ تلقائي) · `RecoveryNotifier` + `RestoreActivity` + `BootReceiver` (الاسترداد الصفري) · `OverlayController` · `GuardPrefs`.
- **القنوات**: `ghadd/control` (إعدادات وموافقة) · `ghadd/system` (تشغيل/إيقاف ومنح) · `ghadd/analyze` (بايتات اللقطة → قرار).
- **قاعدة الذيل الأخير**: قرار الحجب يُنفَّذ في Kotlin — الحماية قائمة حتى لو قُتلت واجهة Flutter.

### نطاق كشف المناطق وحدوده

يضمّ التطبيق كاشف NudeNet YOLOv8m محليًا (18 فئة، 640×640، نحو 51.9MB؛ AGPL-3.0). تُغطّى فئات الثديين والأرداف والأعضاء التناسلية والشرج المكشوفة، إضافةً إلى البطن المكشوف، ثم يُوسّع القناع هندسيًا ليشمل نطاقًا محافظًا من الجذع والحوض وأعلى الفخذين. تُستبعد الوجوه والقدمين والإبطين والأجزاء المصنفة مغطاة. إذا صنّف نموذج الصورة المحتوى على أنه غير آمن ولم يحدد الكاشف موضعًا مستهدفًا، تُستخدم التغطية الكاملة احتياطًا. **هذا ليس نموذج تقسيم أو تقدير وضعية**؛ ولا توجد فئات مستقلة للظهر أو الفخذ، لذلك لا يمكن ضمان الكشف في كل صورة أو وضعية. اختبار المحاكي يتحقق من تحميل TFLite واستدلال صورة رمادية آمنة فقط، وليس قياسًا لمعدل الاستدعاء. المصدر والبصمات والتراخيص موثقة في [`MODEL_LICENSES.md`](MODEL_LICENSES.md).

## الإصدارات المدعومة

| إصدار أندرويد | مسار الالتقاط | ملاحظات |
|---|---|---|
| 11+ (API 30+) | `takeScreenshot` الرسمي لخدمة الوصول | المسار الأساسي |
| 9 و10 (API 28/29) | تصريح عرض الشاشة (MediaProjection) | حوار النظام نفسه — الإطارات في الذاكرة فقط، ويُعاد تأكيده بعد كل إقلاع. منذ 0.3.3: «لا إيقاف أبدًا إلا بيدك» — سقوط الجلسة يُعالَج بالاسترداد الصفري (حوار يُفتح ويُؤكّد آليًا) أو إشعار إنقاذ، والتفصيل في PRIVACY.md |

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
# المتوقع: 9 صلاحيات (7 معلنة + 2 نظاميتان من سلسلة البناء) — ولا شبكية بينها:
#   SYSTEM_ALERT_WINDOW · FOREGROUND_SERVICE · FOREGROUND_SERVICE_SPECIAL_USE
#   FOREGROUND_SERVICE_MEDIA_PROJECTION · POST_NOTIFICATIONS · RECEIVE_BOOT_COMPLETED
#   REQUEST_IGNORE_BATTERY_OPTIMIZATIONS · WAKE_LOCK · DYNAMIC_RECEIVER_*
# التفصيل الكامل في PRIVACY.md
```

## بوابات CI الثلاث (تعمل تلقائيًا على كل PR ودفع)

1. **الجودة**: `flutter analyze` + `flutter test` (عقد العتبات والعدادات).
2. **رفض الإنترنت**: بناء `--release` ثم `aapt2` — فشل فوري عند أي `INTERNET/ACCESS_NETWORK_STATE`، وتطابق حرفي مع القائمة البيضاء الموثقة (7 معلنة + 2 نظاميتان).
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
  GuardAccessibilityService.kt  # الالتقاط + مسار RAM + التوليد/المهلة + النقر الآلي المقيّد
  GuardForegroundService.kt     # الإشعار الدائم + START_STICKY + عدم الإيقاف عند مسح «الأخيرة»
  ProjectionService.kt          # خدمة الالتقاط البديل (9/10) + الإنقاذ عند إعادة تشغيل النظام
  RecoveryNotifier.kt           # الاسترداد الصفري + إشعار الإنقاذ
  RestoreActivity.kt            # النشاط الشفاف لفتح حوار الاسترداد تلقائيًا
  BootReceiver.kt               # بدء الإنقاذ بعد إعادة إقلاع الجهاز
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

GNU AGPL-3.0 — انظر [LICENSE](LICENSE) وإشعار نموذج NudeNet في [`MODEL_LICENSES.md`](MODEL_LICENSES.md). حزمة `third_party/nsfw_detect` تحتفظ بترخيص MIT المنفصل المرفق بها.
