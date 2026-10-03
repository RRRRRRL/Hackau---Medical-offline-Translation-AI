// FieldTalk smoke test: the app builds and shows its main screen.
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldtalk/main.dart';

void main() {
  testWidgets('App renders and shows language selectors', (tester) async {
    await tester.pumpWidget(const FieldTalkApp());
    expect(find.text('FieldTalk'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Target'), findsOneWidget);
  });
}