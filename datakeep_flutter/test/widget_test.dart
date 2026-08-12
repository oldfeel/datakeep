import 'package:flutter_test/flutter_test.dart';
import 'package:datakeep_flutter/app.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const DataKeepApp());
    expect(find.text('DataKeep'), findsWidgets);
  });
}
