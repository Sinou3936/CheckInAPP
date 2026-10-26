import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/main.dart';

import 'helpers/test_db.dart';
import 'helpers/widget_test_helpers.dart';

void main() {
  // 앱 코드가 직접 DB 를 열므로 테스트가 핸들을 쥐지 않는다. 그래도 ffi 초기화는 필요하다.
  setUpAll(initTestDatabaseFactory);

  testWidgets('앱이 뜨면 내비게이션 셸과 대시보드를 그린다', (tester) async {
    // dbPath null 은 인메모리 DB, serverPort 0 은 임의 포트 — 실제 8080 과 다투지 않는다.
    await tester.pumpWidget(const CheckInApp(dbPath: null, serverPort: 0));
    await pumpUntil(tester, () => shown(find.text('실시간 현황')));
    expect(find.text('회원'), findsOneWidget);
    expect(find.text('반'), findsOneWidget);
    expect(find.text('기록'), findsOneWidget);
    expect(find.text('점검'), findsOneWidget);

    // 서버 소켓과 타이머를 정리한다. dispose 는 controller.stop() 을 await 하는 동안 실제
    // 소켓을 닫으므로, 실제 비동기와 프레임을 번갈아 흘려 종료가 끝나게 한다. 한 번의 고정
    // 대기로는 서버가 가짜 비동기 영역에 만든 타이머가 남아 테스트가 실패한다.
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  });
}
