import 'package:flutter_test/flutter_test.dart';

import 'package:po_app/main.dart';

void main() {
  testWidgets('로그인 화면 표시 스모크 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('피오'), findsOneWidget);
    expect(find.text('시공·협업 매칭'), findsOneWidget);
    expect(find.text('네이버로 로그인'), findsOneWidget);
    expect(find.text('카카오톡으로 로그인'), findsOneWidget);
    expect(find.text('구글로 로그인'), findsOneWidget);
  });
}
