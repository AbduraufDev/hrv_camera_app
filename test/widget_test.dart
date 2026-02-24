import 'package:flutter_test/flutter_test.dart';
import 'package:hrv_camera_app/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const HrvApp());
    expect(find.text('HRV Camera'), findsOneWidget);
  });
}
