import 'package:admob_mediation_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    // Pump the widget tree only — ad SDK initialization is triggered from
    // main() and never from widgets, so the UI is fully testable.
    await tester.pumpWidget(const AdMobMediationApp());
    expect(find.text('AdMob Mediation'), findsOneWidget);
  });
}
