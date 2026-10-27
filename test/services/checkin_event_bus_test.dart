import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/checkin_event_bus.dart';

void main() {
  test('발행한 이벤트를 듣는 쪽이 받는다', () async {
    final bus = CheckInEventBus();
    addTearDown(bus.dispose);

    final received = bus.events.first;
    bus.publish(
      const CheckInEvent(memberName: '홍길동', kind: CheckEventKind.checkedIn),
    );

    final event = await received;
    expect(event.memberName, '홍길동');
    expect(event.kind, CheckEventKind.checkedIn);
    expect(event.isLate, isFalse);
    expect(event.remaining, isNull);
  });

  // 차단은 아무것도 기록하지 않으므로 이 통로가 유일한 흔적이다. 남은 시간까지 같이
  // 흘러야 카운터 직원이 "N분 뒤에 다시 오라"고 말할 수 있다.
  test('차단 이벤트는 남은 시간을 함께 들고 온다', () async {
    final bus = CheckInEventBus();
    addTearDown(bus.dispose);

    final received = bus.events.first;
    bus.publish(
      const CheckInEvent(
        memberName: '홍길동',
        kind: CheckEventKind.blockedTooEarly,
        remaining: Duration(minutes: 12),
      ),
    );

    final event = await received;
    expect(event.kind, CheckEventKind.blockedTooEarly);
    expect(event.remaining, const Duration(minutes: 12));
  });

  test('듣는 쪽이 없을 때 발행해도 오류 없이 버려진다', () {
    final bus = CheckInEventBus();
    addTearDown(bus.dispose);
    bus.publish(
      const CheckInEvent(memberName: '홍길동', kind: CheckEventKind.checkedOut),
    );
  });

  test('닫힌 뒤 발행해도 오류가 나지 않는다', () async {
    final bus = CheckInEventBus();
    await bus.dispose();
    bus.publish(
      const CheckInEvent(
        memberName: '홍길동',
        kind: CheckEventKind.blockedOverdue,
      ),
    );
  });
}
