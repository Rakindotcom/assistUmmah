import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/app.dart';

void main() {
  testWidgets('shows app title in offline preview', (tester) async {
    await tester.pumpWidget(const UmmahAssistApp(firebaseReady: false));

    expect(find.text('Ummah Assist'), findsOneWidget);
  });
}
