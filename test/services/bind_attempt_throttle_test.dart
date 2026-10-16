import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/bind_attempt_throttle.dart';

void main() {
  final at = DateTime(2026, 10, 16, 15, 0);

  void fail(
    BindAttemptThrottle throttle,
    int times, {
    String deviceToken = 'device-1',
    int memberId = 1,
    DateTime? now,
  }) {
    for (var i = 0; i < times; i++) {
      throttle.recordFailure(
        deviceToken: deviceToken,
        memberId: memberId,
        now: now ?? at,
      );
    }
  }

  bool locked(
    BindAttemptThrottle throttle, {
    String deviceToken = 'device-1',
    int memberId = 1,
    DateTime? now,
  }) => throttle.isLocked(
    deviceToken: deviceToken,
    memberId: memberId,
    now: now ?? at,
  );

  test('실패가 maxAttempts 에 닿으면 잠긴다', () {
    final throttle = BindAttemptThrottle(maxAttempts: 5);
    fail(throttle, 4);
    expect(locked(throttle), isFalse);
    fail(throttle, 1);
    expect(locked(throttle), isTrue);
  });

  test('lockout 이 지나면 다시 풀린다', () {
    final throttle = BindAttemptThrottle(
      maxAttempts: 5,
      lockout: const Duration(minutes: 10),
    );
    fail(throttle, 5);

    expect(locked(throttle, now: at.add(const Duration(minutes: 9))), isTrue);
    expect(locked(throttle, now: at.add(const Duration(minutes: 11))), isFalse);
  });

  test('clear 는 실패 횟수를 지운다', () {
    final throttle = BindAttemptThrottle(maxAttempts: 5);
    fail(throttle, 4);

    throttle.clear(deviceToken: 'device-1', memberId: 1);

    fail(throttle, 4);
    expect(locked(throttle), isFalse);
  });

  test('기기와 회원이 모두 다른 시도는 서로 영향을 주지 않는다', () {
    final throttle = BindAttemptThrottle(maxAttempts: 5);
    fail(throttle, 5);

    expect(locked(throttle), isTrue);
    expect(locked(throttle, deviceToken: 'device-2', memberId: 2), isFalse);
  });

  test('기기 토큰을 바꿔가며 같은 회원을 5회 틀리면 잠긴다', () {
    final throttle = BindAttemptThrottle(maxAttempts: 5);
    for (var i = 0; i < 5; i++) {
      fail(throttle, 1, deviceToken: 'fresh-$i', memberId: 7);
    }

    expect(locked(throttle, deviceToken: 'fresh-new', memberId: 7), isTrue);
    expect(locked(throttle, deviceToken: 'fresh-new', memberId: 8), isFalse);
  });

  test('회원을 바꿔가며 같은 기기로 5회 틀리면 잠긴다', () {
    final throttle = BindAttemptThrottle(maxAttempts: 5);
    for (var i = 0; i < 5; i++) {
      fail(throttle, 1, deviceToken: 'device-1', memberId: i);
    }

    expect(locked(throttle, deviceToken: 'device-1', memberId: 99), isTrue);
    expect(locked(throttle, deviceToken: 'device-2', memberId: 99), isFalse);
  });

  test('임계에 못 닿은 실패는 lockout 창이 지나면 더는 세지 않는다', () {
    final throttle = BindAttemptThrottle(
      maxAttempts: 5,
      lockout: const Duration(minutes: 10),
    );
    fail(throttle, 4);

    // 창이 지난 뒤의 실패 한 번은 "연속 5회" 가 아니라 새로 시작한 1회다.
    fail(throttle, 1, now: at.add(const Duration(minutes: 11)));

    expect(locked(throttle, now: at.add(const Duration(minutes: 11))), isFalse);
    // 창 안에서 이어진 실패는 그대로 쌓인다.
    fail(throttle, 3, now: at.add(const Duration(minutes: 12)));
    expect(locked(throttle, now: at.add(const Duration(minutes: 12))), isFalse);
    fail(throttle, 1, now: at.add(const Duration(minutes: 12)));
    expect(locked(throttle, now: at.add(const Duration(minutes: 12))), isTrue);
  });
}
