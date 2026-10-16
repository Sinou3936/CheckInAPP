import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/bind_attempt_throttle.dart';

void main() {
  test('실패가 maxAttempts 에 닿으면 잠긴다', () {
    final throttle = BindAttemptThrottle(maxAttempts: 5);
    final at = DateTime(2026, 10, 16, 15, 0);
    for (var i = 0; i < 4; i++) {
      throttle.recordFailure('device-1', now: at);
    }
    expect(throttle.isLocked('device-1', now: at), isFalse);
    throttle.recordFailure('device-1', now: at);
    expect(throttle.isLocked('device-1', now: at), isTrue);
  });

  test('lockout 이 지나면 다시 풀린다', () {
    final throttle = BindAttemptThrottle(
      maxAttempts: 5,
      lockout: const Duration(minutes: 10),
    );
    final at = DateTime(2026, 10, 16, 15, 0);
    for (var i = 0; i < 5; i++) {
      throttle.recordFailure('device-1', now: at);
    }

    expect(
      throttle.isLocked('device-1', now: at.add(const Duration(minutes: 9))),
      isTrue,
    );
    expect(
      throttle.isLocked('device-1', now: at.add(const Duration(minutes: 11))),
      isFalse,
    );
  });

  test('clear 는 실패 횟수를 지운다', () {
    final throttle = BindAttemptThrottle(maxAttempts: 5);
    final at = DateTime(2026, 10, 16, 15, 0);
    for (var i = 0; i < 4; i++) {
      throttle.recordFailure('device-1', now: at);
    }

    throttle.clear('device-1');

    for (var i = 0; i < 4; i++) {
      throttle.recordFailure('device-1', now: at);
    }
    expect(throttle.isLocked('device-1', now: at), isFalse);
  });

  test('기기별로 따로 센다', () {
    final throttle = BindAttemptThrottle(maxAttempts: 5);
    final at = DateTime(2026, 10, 16, 15, 0);
    for (var i = 0; i < 5; i++) {
      throttle.recordFailure('device-1', now: at);
    }

    expect(throttle.isLocked('device-1', now: at), isTrue);
    expect(throttle.isLocked('device-2', now: at), isFalse);
  });
}
