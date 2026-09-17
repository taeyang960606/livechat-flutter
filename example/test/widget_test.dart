import 'package:flutter_test/flutter_test.dart';
import 'package:livechat_example/main.dart';

void main() {
  testWidgets('unconfigured example explains deployment settings', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.textContaining('LIVECHAT_BASE_URL'), findsOneWidget);
    expect(find.text('Open chat (0 unread)'), findsOneWidget);
  });
}
