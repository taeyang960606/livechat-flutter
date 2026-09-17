import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livechat_flutter/livechat_flutter.dart';
import 'package:livechat_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('live deployment reaches ready and can close and reopen', (
    tester,
  ) async {
    await app.main();
    await tester.pump();
    await tester.tap(find.text('Open chat (0 unread)'));
    await tester.pump();
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Chat unavailable').evaluate().isNotEmpty) break;
      if (find.text('Live chat').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    expect(find.text('Live chat'), findsOneWidget);
    expect(
      find.text('Chat unavailable'),
      findsNothing,
      reason: app.status.value,
    );
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason:
          'The widget must emit ready before the loading overlay disappears.',
    );
    expect(
      app.status.value,
      'Ready',
      reason: 'No load or widget error should be reported.',
    );
    await tester.tap(find.byTooltip('Close chat'));
    await tester.pump();
    expect(find.text('Open chat (0 unread)'), findsOneWidget);
    await tester.tap(find.text('Open chat (0 unread)'));
    await tester.pump();
    expect(find.text('Live chat'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Passive smoke test only: no member identity, message or attachment is sent.
    await LiveChat.destroy();
    await tester.pump();
  });
}
