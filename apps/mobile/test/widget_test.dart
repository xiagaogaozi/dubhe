import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dubhe_companion/src/app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows Chinese login screen', (tester) async {
    await tester.pumpWidget(const DubheCompanionApp());

    expect(find.text('创建账号'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('Core 地址'), findsOneWidget);
  });

  testWidgets('restores saved Core URL on login screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      coreUrlPreferenceKey: 'http://10.0.2.2:8000',
    });

    await tester.pumpWidget(const DubheCompanionApp());
    await tester.pump();

    expect(find.text('http://10.0.2.2:8000'), findsOneWidget);
  });
}
