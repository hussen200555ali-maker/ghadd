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

1. افتح تبويب **Actions** — ستعمل بوابات CI الثلاث تلقائيًا:
   - البوابة 1: بناء + تحليل + اختبارات.
   - البوابة 2: رفض `INTERNET` عبر aapt2 + مطابقة الصلاحيات الخمس.
2. أنشئ أول PR إن أردت تدفق العمل الكامل:
   ```bash
   git checkout -b feat/poc-1
   git push -u origin feat/poc-1
   ```
   ثم استخدم نص `docs/PR-1.md` جاهزًا في وصف الـPR.
3. أنشئ Milestones أ3–أ8 من `docs/MILESTONES.md`.
