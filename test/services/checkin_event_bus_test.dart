import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/checkin_event_bus.dart';
import 'package:checkin_app/services/qr_token_service.dart';

void main() {
  test('발행한 이벤트를 듣는 쪽이 받는다', () async {
    final bus = CheckInEventBus();
    addTearDown(bus.dispose);

    final received = bus.events.first;
    bus.publish(const CheckInEvent(memberName: '홍길동', kind: QrKind.checkIn));

    final event = await received;
    expect(event.memberName, '홍길동');
    expect(event.kind, QrKind.checkIn);
    expect(event.isLate, isFalse);
  });

  test('듣는 쪽이 없을 때 발행해도 오류 없이 버려진다', () {
    final bus = CheckInEventBus();
    addTearDown(bus.dispose);
    bus.publish(const CheckInEvent(memberName: '홍길동', kind: QrKind.checkOut));
  });

  test('닫힌 뒤 발행해도 오류가 나지 않는다', () async {
    final bus = CheckInEventBus();
    await bus.dispose();
    bus.publish(const CheckInEvent(memberName: '홍길동', kind: QrKind.checkIn));
  });
}
