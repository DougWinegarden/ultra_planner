import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/auth/auth_gate.dart';
import 'package:ultra_planner/firebase_options.dart';
import 'package:ultra_planner/main.dart';

void main() {
  group('Firebase configuration gate', () {
    test('placeholder options are reported as unconfigured', () {
      // Guards the setup flow: if someone half-fills firebase_options.dart the
      // app must still take the "not configured" path rather than crash.
      expect(DefaultFirebaseOptions.isConfigured, isFalse);
    });

    testWidgets('unconfigured app shows the setup notice, not a crash', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const OceanListsApp());
      await tester.pump();

      expect(find.byType(SetupNoticeScreen), findsOneWidget);
      expect(find.text('Firebase is not configured yet'), findsOneWidget);
    });

    testWidgets('a startup error is surfaced to the user', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const OceanListsApp(startupError: 'network unreachable'),
      );
      await tester.pump();

      expect(find.text('Firebase could not start'), findsOneWidget);
      expect(find.textContaining('network unreachable'), findsOneWidget);
    });
  });
}
