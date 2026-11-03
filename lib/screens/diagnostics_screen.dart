import 'package:flutter/material.dart';
import 'package:nsfw_detect/nsfw_detect.dart';

import '../app.dart';
import '../services/native_bridge.dart';

/// شاشة التشخيص — الشفافية المطلقة عمليًا: يرى المستخدم بأم عينه
/// حالة كل مكوّن (الصلاحيات، الالتقاط، النموذج) ويسوق اختبارات مباشرة،
/// مع سجل الأحداث الأصلي (ذاكرة فقط، يمسح بموت العملية).
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, dynamic> _perms = const {};
  Map<String, dynamic> _proj = const {};
  Map<String, dynamic> _model = const {};
  Map<String, dynamic> _battery = const {};
  List<String> _logs = const [];
  String _captureResult = '';
  String _scanResult = '';
  String _batteryResult = '';
  bool _busyCapture = false;
  bool _busyScan = false;
  bool _busyBattery = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    _perms = await GuardSystem.permissionStatus();
    _proj = await GuardSystem.projectionStatus();
    _model = await GuardSystem.prepareModel();
    _battery = await GuardSystem.batteryStatus();
    _logs = await GuardSystem.guardLogs();
    if (mounted) setState(() {});
  }

  /// [0.3.2] طلب استثناء البطارية من التشخيص — نفس بطاقة الشاشة الرئيسية.
  Future<void> _runBatteryExemption() async {
    setState(() {
      _busyBattery = true;
      _batteryResult = 'جارٍ فتح حوار النظام…';
    });
    final r = await GuardSystem.requestBatteryExemption();
    if (!mounted) return;
    if (r['exempt'] == true) {
      setState(() {
        _busyBattery = false;
        _batteryResult = 'مستثنى مسبقًا ✓ — الحماية في أمان من قتل الخلفية';
      });
    } else if (r['opened'] == true) {
      // الحوار أمام المستخدم الآن — القرار بيدك، والحالة تُقرأ عند العودة
      setState(() {
        _busyBattery = false;
        _batteryResult = 'فُتح حوار النظام «السماح بالعمل دائمًا في الخلفية؟» — '
            'اختر السماح ثم عد إلى التطبيق (تُحدّث الحالة تلقائيًا).';
      });
    } else {
      setState(() {
        _busyBattery = false;
        _batteryResult = 'تعذر فتح الحوار على هذا الجهاز — امنح الاستثناء يدويًا: '
            'الإعدادات ← التطبيقات ← غَضّ ← البطارية ← «غير محسّن».';
      });
    }
    await _refresh();
  }

  Future<void> _runCaptureTest() async {
    // [0.3.1] فحص فوري قبل النداء: إن كانت الجلسة ساقطة فالرسالة وحدها كافية —
    // ومحرك الالتقاط سيعيد نفس السبب من الجهة الأصلية إن تغيرت الحالة الآن.
    await _refresh();
    if (!mounted) return;
    if (_proj['legacy'] == true && _proj['active'] != true) {
      setState(() {
        _captureResult =
            'جلسة تصريح العرض غير نشطة الآن — أعد تفعيلها من بطاقة «تفعيل تصريح '
            'عرض الشاشة» في الشاشة الرئيسية (نقرة واحدة) ثم كرر هذا الاختبار. '
            'الجلسة تُسقط بموت العملية بحكم النظام (مسح التطبيق من الأخيرة، قتل '
            'الخلفية، إعادة الإقلاع) — لا تُخزّن أبدًا.';
      });
      return;
    }
    setState(() {
      _busyCapture = true;
      _captureResult = 'جارٍ الالتقاط…';
    });
    final r = await GuardSystem.testCapture();
    if (!mounted) return;
    setState(() {
      _busyCapture = false;
      _captureResult = r['ok'] == true
          ? 'نجح الالتقاط — ${(r['bytes'] as num?) ?? 0} بايت في ${(r['ms'] as num?) ?? 0} مللي ثانية'
          : 'فشل: ${r['note'] ?? r['ok']}';
    });
    await _refresh();
  }

  Future<void> _runScanTest() async {
    setState(() {
      _busyScan = true;
      _scanResult = 'جارٍ الفحص التجريبي (قد يستغرق أولًا بضع ثوانٍ لتحميل النموذج)…';
    });
    try {
      final ok = await GuardBrain.ensure();
      if (!ok) {
        setState(() {
          _busyScan = false;
          _scanResult = 'النموذج غير جاهز — راجع حالة النموذج أعلاه';
        });
        return;
      }
      final dynamic result = await NsfwDetector.instance.scanBytes(
        GuardBrain.warmupJpeg,
        modelId: GuardBrain.modelId,
        confidenceThreshold: 0.7,
      );
      final labels = <String>[];
      try {
        for (final l in result.labels as List) {
          labels.add('${l.category.toString().split('.').last}: ${(l.confidence as num).toStringAsFixed(3)}');
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _busyScan = false;
        _scanResult = 'نجح الفحص ✓ — الفئات: ${labels.join(' · ')}';
      });
      await GuardSystem.logNative('اختبار الكشف الذاتي: نجح — $labels');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyScan = false;
        _scanResult = 'فشل الفحص: $e';
      });
      await GuardSystem.logNative('✗ اختبار الكشف الذاتي فشل: $e');
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التشخيص')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _row('خدمة إمكانية الوصول', _yesNo(_perms['accessibility'] == true)),
            _row('العرض فوق التطبيقات', _yesNo(_perms['overlay'] == true)),
            _row('تصريح عرض الشاشة (أندرويد 9/10)',
                _proj['legacy'] == true
                    ? (_proj['active'] == true ? 'منح والمحرك يعمل' : 'لم يُمنح بعد')
                    : 'غير مطلوب (أندرويد 11+)'),
            _row('استثناء من تحسين البطارية (مقاومة النوم)',
                _battery['exempt'] == true ? 'مستثنى ✓' : 'غير مستثنى ✗'),
            _row('نموذج الكشف المدمج',
                _model['ok'] == true ? 'جاهز — ${_model['path'] ?? ''}' : 'غير جاهز!'),
            _row('نسخة أندرويد (API)', '${_perms['sdk'] ?? '?'}'),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busyCapture ? null : _runCaptureTest,
              child: const Text('اختبار الالتقاط (أندرويد 9/10)'),
            ),
            if (_captureResult.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_captureResult, style: const TextStyle(fontSize: 12.5)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busyBattery ? null : _runBatteryExemption,
              child: const Text('مقاومة النوم — طلب استثناء البطارية'),
            ),
            if (_batteryResult.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_batteryResult, style: const TextStyle(fontSize: 12.5)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busyScan ? null : _runScanTest,
              child: const Text('اختبار الكشف الذاتي'),
            ),
            if (_scanResult.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(_scanResult, style: const TextStyle(fontSize: 12.5)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                const Text('سجل الأحداث (ذاكرة فقط — بلا قرص)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(onPressed: _refresh, child: const Text('تحديث')),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GuardTheme.navy,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _logs.isEmpty
                  ? const Text('لا أحداث بعد — شغّل الحماية أو افتح التطبيق',
                      style: TextStyle(color: GuardTheme.teal, fontSize: 12))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final l in _logs.reversed)
                          SelectableText(l,
                              style: const TextStyle(
                                  color: Color(0xFFBFE8F0),
                                  fontSize: 11.5,
                                  height: 1.5)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: value.contains('✓') || value.contains('منح') ||
                            value.contains('جاهز')
                        ? GuardTheme.tealDeep
                        : GuardTheme.muted,
                    fontSize: 12.5)),
          ],
        ),
      );

  String _yesNo(bool v) => v ? 'ممنوح ✓' : 'غير ممنوح ✗';
}
