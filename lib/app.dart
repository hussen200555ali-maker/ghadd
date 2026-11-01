import 'package:flutter/material.dart';

import 'screens/disclosure_screen.dart';
import 'screens/home_screen.dart';
import 'services/native_bridge.dart';

/// الهوية البصرية للوثيقة: كحلي داكن + فيروزي (نفس نظام دراسة الجدوى)
class GuardTheme {
  static const navy = Color(0xFF0A1A2E);
  static const navy2 = Color(0xFF12263F);
  static const thead = Color(0xFF1A4A72);
  static const teal = Color(0xFF3FB6C9);
  static const tealDeep = Color(0xFF1D7F96);
  static const page = Color(0xFFF5F8FC);
  static const card = Color(0xFFE8EFF8);
  static const border = Color(0xFFC5D4E4);
  static const text = Color(0xFF14283E);
  static const muted = Color(0xFF52708C);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: tealDeep,
        primary: tealDeep,
        secondary: teal,
        surface: page,
      ),
      scaffoldBackgroundColor: page,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Color(0xFFE8F0F8),
        centerTitle: true,
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: tealDeep, foregroundColor: Colors.white),
      ),
    );
  }
}

class GhaddApp extends StatelessWidget {
  const GhaddApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'غَضّ',
      debugShowCheckedModeBanner: false,
      theme: GuardTheme.theme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      home: const Bootstrap(),
    );
  }
}

/// بوابة الإقلاع: استعادة الحالة ثم التوجيه —
/// بلا موافقة الإفصاح البارز لا تُعرض الشاشة الرئيسية أبدًا (وثيقة الردّ ص8).
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  bool? _consented;

  @override
  void initState() {
    super.initState();
    GuardSettings.load().then((_) {
      if (mounted) setState(() => _consented = GuardSettings.consent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _consented;
    if (state == null) {
      // شاشة انتظار قصيرة أثناء قراءة التفضيلات المحلية
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: GuardTheme.navy,
          body: Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                border: Border.all(color: GuardTheme.teal, width: 2.5),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Text('غ',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: GuardTheme.teal)),
            ),
          ),
        ),
      );
    }
    return state
        ? const HomeScreen()
        : DisclosureScreen(onDone: () => setState(() => _consented = true));
  }
}
