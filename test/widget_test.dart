// Basic smoke test for Electric Attendance app
//
// This test verifies that the app can start without errors.
// For comprehensive testing, add unit tests for:
// - FaceService (embedding generation/comparison)
// - LocationService (distance calculations)
// - AttendanceRepository

import 'package:flutter_test/flutter_test.dart';
import 'package:electric_attendance/main.dart';

void main() {
  testWidgets('App launches without errors', (WidgetTester tester) async {
    // Build our app and trigger a frame
    await tester.pumpWidget(const MyApp());

    // Verify the app widget tree was created
    expect(find.byType(MyApp), findsOneWidget);
  });
}
