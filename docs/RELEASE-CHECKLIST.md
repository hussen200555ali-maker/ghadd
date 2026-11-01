# قائمة إطلاق v0.1.0-alpha

## قبل الوسم

1. [ ] CI أخضر على main (البوابتان: الجودة + رفض INTERNET عبر aapt2).
2. [ ] `flutter build apk --release` على جهاز المطور + فحص `aapt2 dump badging` يدويًا.
3. [ ] تجربة يدوية على جهاز حقيقي: الإفصاح → منح الوصول → منح Overlay → تشغيل →
       فتح متصفح بمحتوى اختباري → الحجب → العدادات تزيد.
4. [ ] تحديث `CHANGELOG.md` بالتاريخ الفعلي.

## الوسم والإصدار

```bash
git tag -a v0.1.0-alpha -m "إثبات الفكرة: الإفصاح البارز + مسار اللقطة في RAM + بوابات CI"
git push origin v0.1.0-alpha
```

ثم في GitHub → Releases → **Draft a new release**:
- Tag: `v0.1.0-alpha`
- العنوان: `غَضّ v0.1.0-alpha — إثبات الفكرة`
- الوصف: انسخ قسم «أُضيف» من CHANGELOG.md + جدول الصلاحيات الخمس من PRIVACY.md
- أرفق: `app-release.apk` + **ناتج `aapt2 dump badging` في ملف نصي** (دليل الشفافية)

## التوقيع (قبل أي توزيع خارج التجريب الشخصي)

- أنشئ keystore خاصًا واحفظه خارج المستودع (`*.jks` مُهمَل أصلًا في .gitignore).
- استبدل `signingConfig = signingConfigs.debug` في `build.gradle` بمفتاحك.
- لا ترفع أي keystore إلى المستودع إطلاقًا.

## بعد الإصدار

- [ ] دعوة 10 مختبرين وفق بروتوكول القياس (الملحق ب من دراسة الجدوى).
- [ ] فتح Milestones أ3–أ8 في GitHub من docs/MILESTONES.md.
- [ ] بيانات fastlane لأول مسودة F-Droid (تُكتب في أ8).
