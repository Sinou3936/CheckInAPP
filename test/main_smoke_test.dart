import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/main.dart';

import 'helpers/widget_test_helpers.dart';

void main() {
  testWidgets('앱이 뜨면 내비게이션 셸과 대시보드를 그린다', (tester) async {
    // dbPath null 은 인메모리 DB, serverPort 0 은 임의 포트 — 실제 8080 과 다투지 않는다.
    await tester.pumpWidget(const CheckInApp(dbPath: null, serverPort: 0));
    await pumpUntil(tester, () => shown(find.text('실시간 현황')));
    expect(find.text('회원'), findsOneWidget);
    expect(find.text('반'), findsOneWidget);
    expect(find.text('기록'), findsOneWidget);

    // 서버 소켓과 타이머를 정리한다.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  });
}
