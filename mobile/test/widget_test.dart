// FieldTalk smoke test: the app builds and shows its main screen.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show Size;

import 'package:fieldtalk/main.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('Main screen fits $width dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const FieldTalkApp());
      await tester.pump();
      expect(find.text('FieldTalk'), findsOneWidget);
      expect(find.text('SOURCE'), findsOneWidget);
      expect(find.text('TARGET'), findsOneWidget);
      expect(find.text('03  QUICK QUESTIONS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
