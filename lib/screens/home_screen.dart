import 'package:flutter/material.dart';

import '../app.dart';
import '../services/native_bridge.dart';
import 'settings_screen.dart';

/// الشاشة الرئيسية: معالج إعداد من ثلاث خطوات + مفتاح الحماية + عدادات محلية.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _accessibilityOk = false;
  bool _overlayOk = false;
  Map<String, dynamic> _stats = const {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    _stats = await GuardSettings.stats();
    if (mounted) setState(() {});
  }

  Future<void> _toggleProtection(bool value) async {
    if (value && (!_accessibilityOk || !_overlayOk)) {
      _showSetupHint();
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
      appBar: AppBar(title: const Text('غَضّ')),
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
                setState(() => _accessibilityOk = true);
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
                setState(() => _overlayOk = true);
              },
            ),
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
