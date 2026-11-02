// تدخين الواجهات: شاشة الإفصاح — بوابة التطبيق بأكمله — يجب أن تُبنى دون استثناءات.
// (وجود هذا الملف يمنع flutter create في CI من توليد قالب widget_test يشير إلى MyApp)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghadd/screens/disclosure_screen.dart';

void main() {
  testWidgets('شاشة الإفصاح تُبنى دون استثناءات', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DisclosureScreen(onDone: () {})),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(DisclosureScreen), findsOneWidget);
  });
}
