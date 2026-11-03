import 'package:flutter/material.dart';

import '../app.dart';
import '../services/native_bridge.dart';
import 'diagnostics_screen.dart';
import 'settings_screen.dart';

/// الشاشة الرئيسية: معالج إعداد من ثلاث خطوات + مفتاح الحماية + عدادات محلية.
/// حالة الصلاحيات تُقرأ من النظام مباشرة (permissionStatus) — لا ذاكرة واجهة:
/// كل فتح جديد للتطبيق أو عودة من الإعدادات يُحدّث البطاقات بالحقيقة الفعلية.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _accessibilityOk = false;
  bool _overlayOk = false;
  Map<String, dynamic> _stats = const {};
  // حالة مسار الالتقاط البديل (أندرويد 9/10) — legacy=true تعني ظهور بطاقة التصريح
  bool _legacyAndroid = false;
  bool _projectionActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // العودة من شاشات منح الصلاحيات (النظام فوقنا ثم نعود) — نقرأ الحقيقة فورًا
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    _stats = await GuardSettings.stats();
    final proj = await GuardSystem.projectionStatus();
    _legacyAndroid = proj['legacy'] == true;
    _projectionActive = proj['active'] == true;
    // الإصلاح: الحالة من النظام لا من نقرات سابقة — كانت البطاقات تعود
    // «غير منجزة» عند كل فتح جديد فيرفض المفتاح رغم المنح الفعلي.
    try {
      final st = await GuardSystem.permissionStatus();
      _accessibilityOk = st['accessibility'] == true;
      _overlayOk = st['overlay'] == true;
    } catch (_) {/* بلا قناة أصلية (اختبار): تبقى كما هي */}
    if (mounted) setState(() {});
  }

  Future<void> _toggleProtection(bool value) async {
    if (value && (!_accessibilityOk || !_overlayOk)) {
      _showSetupHint();
      return;
    }
    if (value && _legacyAndroid && !_projectionActive) {
      // [0.3.1] الاسترداد بضغطة واحدة: بدل رسالة تحجب الحماية فقط، نفتح حوار
      // النظام فورًا من المفتاح نفسه — المنح يعيد المستخدم للحماية مباشرة.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: GuardTheme.navy2,
          content: Text('أكمل حوار تصريح عرض الشاشة ثم شغّل الحماية — الجلسة تعيش طالما التطبيق مستمر.'),
          duration: Duration(seconds: 4),
        ),
      );
      await GuardSystem.startProjection();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final proj = await GuardSystem.projectionStatus();
      if (!mounted) return;
      setState(() {
        _legacyAndroid = proj['legacy'] == true;
        _projectionActive = proj['active'] == true;
      });
      return;
    }
    setState(() => GuardSettings.enabled = value);
    await GuardSettings.sync();
    if (value) {
      await GuardSystem.startGuard();
    } else {
      await GuardSystem.stopGuard();
    }
    await _refresh();
  }

  void _showSetupHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: GuardTheme.navy2,
        content: Text('أكمل خطوتي الإعداد أولًا: خدمة الوصول ثم العرض فوق التطبيقات.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('غَضّ'),
        actions: [
          IconButton(
            tooltip: 'التشخيص',
            icon: const Icon(Icons.monitor_heart_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _setupCard(
              step: 1,
              title: 'منح خدمة إمكانية الوصول',
              body: 'تلتقط التطبيق لقطة الشاشة عند تغيّر المحتوى وينزّلها على الجهاز بالكامل.',
              done: _accessibilityOk,
              action: () async {
                await GuardSystem.openAccessibilitySettings();
                // الحالة تُحدّث تلقائيًا عند العودة (didChangeAppLifecycleState)
              },
            ),
            const SizedBox(height: 10),
            _setupCard(
              step: 2,
              title: 'منح العرض فوق التطبيقات',
              body: 'لاستظهار طبقة الطمس فوق أي تطبيق آخر لحظة الكشف.',
              done: _overlayOk,
              action: () async {
                await GuardSystem.openOverlaySettings();
                // الحالة تُحدّث تلقائيًا عند العودة (didChangeAppLifecycleState)
              },
            ),
            // بطاقة أندرويد 9/10 حصرًا: تصريح عرض الشاشة لمسار الالتقاط البديل
            if (_legacyAndroid) ...[
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _projectionActive
                        ? GuardTheme.tealDeep
                        : GuardTheme.card,
                    foregroundColor: _projectionActive
                        ? Colors.white
                        : GuardTheme.muted,
                    child: Icon(_projectionActive
                        ? Icons.check
                        : Icons.screen_share),
                  ),
                  title: const Text('تفعيل تصريح عرض الشاشة',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                    'أندرويد 9/10 يلتقط عبر هذا التصريح. الجلسة تعيش طالما عمل '
                    'التطبيق مستمر — وإذا ماتت العملية (مسح التطبيق من الأخيرة، '
                    'قتل النظام للخلفية، إعادة الإقلاع) يعيد النظام طلبها عمدًا '
                    '(لا تُخزّن أبدًا). الاسترداد بنقرة واحدة هنا أو من مفتاح الحماية. '
                    'على سامسونج: اجعل التطبيق «لا ينام» من إعدادات البطارية.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      await GuardSystem.startProjection();
                      // المحرك يبدأ بعد إغلاق الحوار بجزء من الثانية — نحدّث بعدها
                      await Future<void>.delayed(const Duration(milliseconds: 900));
                      final proj = await GuardSystem.projectionStatus();
                      if (!mounted) return;
                      setState(() {
                        _legacyAndroid = proj['legacy'] == true;
                        _projectionActive = proj['active'] == true;
                      });
                    },
                    child: Text(_projectionActive ? 'إعادة تأكيد' : 'تفعيل'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _setupCard(
              step: 3,
              title: 'اختر حساسية الكشف',
              body: 'صارم 0.85 · متوازن 0.7 · متساهل 0.5 — قابل للتعديل من الإعدادات في أي وقت.',
              done: true,
              action: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: SwitchListTile(
                activeThumbColor: GuardTheme.tealDeep,
                title: const Text('الحماية الآن',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  GuardSettings.enabled
                      ? 'نشطة — تحليل محلي بلا أي اتصال بالشبكة'
                      : 'متوقفة — مفعّلة بيدك ومتوقفة بيدك',
                ),
                value: GuardSettings.enabled,
                onChanged: _toggleProtection,
              ),
            ),
            const SizedBox(height: 18),
            Text('العدادات المحلية', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                _statCard('اليوم', '${_stats['blocked_today'] ?? 0}'),
                const SizedBox(width: 10),
                _statCard('الإجمالي', '${_stats['blocked_total'] ?? 0}'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'آخر طمس: ${(_stats['last_blocked_app'] ?? '').toString().isEmpty ? 'لا شيء بعد' : _stats['last_blocked_app']}',
              style: const TextStyle(color: GuardTheme.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 22),
            const Text(
              'أذونات هذا التطبيق لا تشمل صلاحية INTERNET إطلاقًا — '
              'افحص بنفسك: aapt dump badging app-release.apk | grep uses-permission',
              style: TextStyle(color: GuardTheme.tealDeep, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupCard({
    required int step,
    required String title,
    required String body,
    required bool done,
    required VoidCallback action,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: done ? GuardTheme.tealDeep : GuardTheme.card,
          foregroundColor: done ? Colors.white : GuardTheme.muted,
          child: done ? const Icon(Icons.check) : Text('$step'),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(body, style: const TextStyle(fontSize: 12.5)),
        trailing: TextButton(onPressed: action, child: Text(done ? 'تعديل' : 'تنفيذ')),
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: GuardTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: GuardTheme.tealDeep)),
            Text(label, style: const TextStyle(fontSize: 12, color: GuardTheme.muted)),
          ],
        ),
      ),
    );
  }
}
