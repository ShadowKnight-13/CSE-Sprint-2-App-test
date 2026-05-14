import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mileage_tracker/main.dart';

void main() {
  testWidgets('shows mileage tracker dashboard', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const MileageTrackerApp());
    await tester.pumpAndSettle();

    expect(find.text('Mileage Tracker'), findsOneWidget);
    expect(find.text('Track miles while you drive'), findsOneWidget);
    expect(find.text('Start drive'), findsOneWidget);
  });
}
