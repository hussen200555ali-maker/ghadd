import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../services/native_bridge.dart';

/// إعدادات الحساسية والقائمة البيضاء — كله محلي، بلا أي حساب أو مزامنة.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _pkgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // القيم الحالية محفوظة في متغيرات GuardSettings منذ بدء التطبيق
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    await GuardSettings.sync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: GuardTheme.navy2, content: Text('حُفظت الإعدادات محليًا')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('حساسية الكشف (عتبة الثقة)'),
            Slider(
              value: GuardSettings.threshold,
              min: 0.5,
              max: 0.85,
              divisions: 7,
              label: GuardSettings.threshold.toStringAsFixed(2),
              onChanged: (v) => setState(() => GuardSettings.threshold = v),
              onChangeEnd: (_) => _save(),
            ),
            Text(
              _thresholdHint(GuardSettings.threshold),
              style: const TextStyle(color: GuardTheme.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            // التغطية الموسّعة — بطلب مالك التطبيق: تضم المحتوى غير المحتشم
            // (أجساد مكشوفة/ضيقة) وليس الإباحي الصريح فقط، بعتبة فعليّة 0.45.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: GuardTheme.tealDeep,
              title: const Text('التغطية الموسّعة',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                'يمسك المحتوى غير المحتشم (أجساد مكشوفة/ضيقة، شاطئ…) وليس الصريح فقط — '
                'بتخفيض حد الكشف الفعلي إلى 0.45. قد يزيد الإزعاج (طمس إضافي لمحتوى عادي) — أوقفه متى شئت.',
                style: TextStyle(fontSize: 12.5),
              ),
              value: GuardSettings.expandedCoverage,
              onChanged: (v) {
                setState(() => GuardSettings.expandedCoverage = v);
                _save();
              },
            ),
            const SizedBox(height: 8),
            // [0.4.0] وضع المناطق — كشف NudeNet وتغطية هندسية واسعة.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: GuardTheme.tealDeep,
              title: const Text('تغطية المناطق المكتشفة فقط',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                'يكشف NudeNet الثديين والأرداف والأعضاء الحساسة المكشوفة والبطن، '
                'ثم يوسّع القناع حولها. تُستبعد الوجوه والقدمين والأجزاء المغطاة. '
                'يبقى اللمس والتمرير فعالين؛ وعند إنذار المصنّف دون موضع موثوق تُطبّق '
                'التغطية الكاملة احتياطًا. لا يضمن النموذج كشف الظهر أو الفخذين أو كل وضعية.',
                style: TextStyle(fontSize: 12.5),
              ),
              value: GuardSettings.regionMode,
              onChanged: (v) {
                setState(() => GuardSettings.regionMode = v);
                _save();
              },
            ),
            const SizedBox(height: 22),
            const Text('القائمة البيضاء — حزم تطبيقات تُتجاهل بالكامل'),
            const Text(
              'أدخل اسم الحزمة (مثل com.example.app). لا نطلب صلاحية جرد التطبيقات إطلاقًا '
              'لتجنب صلاحية QUERY_ALL_PACKAGES الحساسة — الإدخال اليدوي أهدأ.',
              style: TextStyle(color: GuardTheme.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pkgCtrl,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      hintText: 'com.example.app',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final v = _pkgCtrl.text.trim();
                    if (v.isEmpty) return;
                    setState(() {
                      if (!GuardSettings.whitelist.contains(v)) {
                        GuardSettings.whitelist.add(v);
                      }
                      _pkgCtrl.clear();
                    });
                    _save();
                  },
                  child: const Text('إضافة'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...GuardSettings.whitelist.map(
              (pkg) => ListTile(
                dense: true,
                leading: const Icon(Icons.shield_outlined, color: GuardTheme.tealDeep),
                title: Text(pkg, style: const TextStyle(fontSize: 13)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () {
                    setState(() => GuardSettings.whitelist.remove(pkg));
                    _save();
                  },
                ),
              ),
            ),
            const Divider(height: 28),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: const Text('التراخيص ومصدر النموذج'),
              subtitle: const Text('NudeNet · AGPL-3.0 · إشعارات الأوزان المضمّنة'),
              trailing: const Icon(Icons.open_in_new),
              onTap: _showModelLicenses,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showModelLicenses() async {
    final bundle = DefaultAssetBundle.of(context);
    final notices = await bundle.loadString('MODEL_LICENSES.md');
    final license = await bundle.loadString('LICENSE');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('التراخيص وإشعارات النموذج'),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: SingleChildScrollView(
            child: SelectableText('$notices\n\n$license'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  String _thresholdHint(double t) {
    if (t >= 0.85) return 'صارم: يطمس أقل، لكن قد يفلت شيء من حين لآخر.';
    if (t >= 0.7) return 'متوازن: التوصية الافتراضية وفق معايير القبول في الوثيقة.';
    return 'متساهل: يطمس أكثر، وقد يطمس أشياء بريئة أحيانًا.';
  }
}
