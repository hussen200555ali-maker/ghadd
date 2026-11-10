# إشعارات النماذج والتراخيص

## كاشف المناطق NudeNet

- **الملف المضمّن:** `assets/models/nsfw_regions.tflite`
- **المصدر المباشر للنسخة المحوّلة إلى TFLite:** [إصدار `models-v1` لمشروع flutter_nsfw_scaner](https://github.com/nexas105/flutter_nsfw_scaner/releases/tag/models-v1)، الملف `NudeNetDetector.tflite.zip`.
- **SHA-256 للأرشيف المنزّل:** `f8d115d8aca1ba2ba488843fd7073e9d7263dbbb65cf2983d81ae52eb32caf4d`
- **SHA-256 لملف TFLite المضمّن بعد فك الأرشيف:** `20974db0e4bc3f158af86d9fc58315a801bbb8ba7dd26e005d6bf8b650df1e33`
- **الحجم:** 51,911,990 بايت؛ إدخال مربّع 640×640، و18 فئة كشف.
- **المشروع الأصلي للأوزان:** [notAI-tech/NudeNet](https://github.com/notAI-tech/NudeNet)، المرخّص بموجب GNU AGPL-3.0. لذلك رُخّص مصدر تطبيق غَضّ الموزّع بموجب AGPL-3.0؛ راجع `LICENSE`. تبقى حزمة `third_party/nsfw_detect` ومكوناتها ذات تراخيصها المنفصلة كما هو موثق في مجلدها.

ترتيب الفئات في النموذج، ويجب أن يطابق `GuardBrain.regionsClassLabels`:

1. `FEMALE_GENITALIA_COVERED`
2. `FACE_FEMALE`
3. `BUTTOCKS_EXPOSED`
4. `FEMALE_BREAST_EXPOSED`
5. `FEMALE_GENITALIA_EXPOSED`
6. `MALE_BREAST_EXPOSED`
7. `ANUS_EXPOSED`
8. `FEET_EXPOSED`
9. `BELLY_COVERED`
10. `FEET_COVERED`
11. `ARMPITS_COVERED`
12. `ARMPITS_EXPOSED`
13. `FACE_MALE`
14. `BELLY_EXPOSED`
15. `MALE_GENITALIA_EXPOSED`
16. `ANUS_COVERED`
17. `FEMALE_BREAST_COVERED`
18. `BUTTOCKS_COVERED`

تُمرّر سياسة غَضّ إلى التغطية الفئات المكشوفة المستهدفة (الثديان، الأرداف، الأعضاء التناسلية، الشرج، والبطن المكشوف)، وتستبعد الوجه والقدمين والإبطين والأجزاء المصنّفة مغطاة. بعد الكشف، يوسّع التطبيق المربع هندسيًا؛ وعند إنذار المصنّف مع عدم وجود موضع موثوق يستخدم التغطية الكاملة احتياطًا.

**حدود مهمة:** لا توجد في هذه الفئات تسمية مستقلة للظهر أو الفخذ، والنموذج ليس مقدّر وضعية أو نموذج تقسيم دلالي. قد يفوّت صورًا بسبب الاتجاه أو الحجب أو الدقة أو الإضاءة؛ لا توجد ضمانة لاكتشاف كل منطقة أو كل وضعية. اختبار المحاكي يثبت تحميل TFLite وعقد الاستدلال على صورة رمادية آمنة، ولا يُعدّ قياسًا لسلامة الكشف أو لمعدل الاستدعاء. يلزم تقييم مستقل على مجموعة صور ممثلة ومرخّصة قبل الاعتماد عليه في أي قرار عالي المخاطر.

## مكونات أخرى

الحزمة المضيفة `third_party/nsfw_detect` مرخّصة بموجب MIT؛ راجع `third_party/nsfw_detect/LICENSE` و`third_party/nsfw_detect/VENDORED.md`. كل مكوّن ذي ترخيص خاص يحتفظ بإشعاره المنفصل.
