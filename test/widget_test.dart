import 'package:ai_chat/src/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the voice-only assistant shell', (tester) async {
    await tester.pumpWidget(const HaruApp());
    await tester.pump();

    expect(find.text('하루'), findsOneWidget);
    expect(find.text('오프라인'), findsOneWidget);
  });
}
