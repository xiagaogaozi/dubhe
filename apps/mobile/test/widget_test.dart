import 'package:flutter_test/flutter_test.dart';

import 'package:dubhe_companion/src/app.dart';

void main() {
  testWidgets('shows Chinese login screen', (tester) async {
    await tester.pumpWidget(const DubheCompanionApp());

    expect(find.text('创建账号'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('Core 地址'), findsOneWidget);
  });
}
