import 'package:flutter_test/flutter_test.dart';
import 'package:mydata_flutter/app.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyDataApp());
    expect(find.text('MyData'), findsWidgets);
  });
}
