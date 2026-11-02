# دفع المستودع إلى GitHub

المستودع مهيأ محليًا بفرع `main` والتاريخ الكامل للالتزامات، والبُعد البعيد مضبوط مسبقًا:

```
origin → https://github.com/hussen200555ali-maker/ghadd.git
```

## الطريقة الأسهل (من جهازك، بمصادقة المتصفح)

```bash
cd ghadd-android
git push -u origin main
```

سيسألك git عن اسم المستخدم وكلمة مرور — **كلمة المرور هنا هي Personal Access Token**
وليس كلمة حسابك:

1. GitHub → Settings → Developer settings → **Personal access tokens → Tokens (classic)**
2. Generate new token (classic) → علّم `repo` فقط → توليد ونسخ.
3. ألصقه في خانة Password. (أو استخدم `gh auth login` إن كان GitHub CLI مثبتًا).

## بديل: الدفع بأمر واحد مع الـToken

```bash
git remote set-url origin https://<TOKEN>@github.com/hussen200555ali-maker/ghadd.git
git push -u origin main
```

> تنبيه: هذه الطريقة تخزّن الـToken في ملف الإعدادات المحلي — مناسبة لجهازك الشخصي فقط.
> بعد الدفع الأول أعد الرابط النظيف:
> ```bash
> git remote set-url origin https://github.com/hussen200555ali-maker/ghadd.git
> ```

## بعد الدفع مباشرة

1. افتح تبويب **Actions** — ستعمل بوابات CI تلقائيًا:
   - البوابة 1: بناء + تحليل + اختبارات.
   - البوابة 2: رفض `INTERNET` عبر aapt2 + مطابقة القائمة البيضاء الموثقة (5 معلنة + 2 نظاميتان).

## كيف تحصل على ملف APK (بلا أي أدوات على جهازك)

1. افتح تبويب **Actions** في المستودع → اضغط على آخر run ناجح (✓).
2. انزل إلى قسم **Artifacts** أسفل الصفحة → نزّل **ghadd-release-apk**.
3. هذا ملف `app-release.apk` بنسخة الإصدار — خرج **فقط** بعد اجتياز بوابة aapt2،
   أي أنه مضمون: بلا صلاحية إنترنت، وبـ7 صلاحيات موثقة حرفيًا (5 معلنة + 2 نظاميتان، ولا شبكية بينها).
4. يمكنك إعادة التوليد متى شئت من زر **Run workflow** (workflow_dispatch).

> ملاحظة: بناء `--debug` يضيف صلاحية INTERNET تلقائيًا من أدوات Flutter، لذا الملف
> المُصدَّر دائمًا هو بناء `--release` — نفس ما سيستخدمه المستخدم النهائي.

## إصدار موسوم (اختياري — يُرفق الـAPK بصفحة Releases تلقائيًا)

```bash
git tag v0.1.0-alpha
git push origin v0.1.0-alpha
```

سيعمل سير العمل على الوسم، وعند نجاح البوابتين يُرفق `app-release.apk`
مباشرة في صفحة **Releases** بالوسم نفسه.

## أول PR إن أردت تدفق العمل الكامل

```bash
git checkout -b feat/poc-1
git push -u origin feat/poc-1
```

ثم استخدم نص `docs/PR-1.md` جاهزًا في وصف الـPR، وأنشئ Milestones أ3–أ8 من `docs/MILESTONES.md`.
