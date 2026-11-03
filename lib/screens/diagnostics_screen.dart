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
  List<String> _logs = const [];
  String _captureResult = '';
  String _scanResult = '';
  bool _busyCapture = false;
  bool _busyScan = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    _perms = await GuardSystem.permissionStatus();
    _proj = await GuardSystem.projectionStatus();
    _model = await GuardSystem.prepareModel();
    _logs = await GuardSystem.guardLogs();
    if (mounted) setState(() {});
  }

  Future<void> _runCaptureTest() async {
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
