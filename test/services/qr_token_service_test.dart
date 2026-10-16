import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/qr_token_service.dart';

void main() {
  test('등원 토큰과 하원 토큰은 서로 다르다', () {
    final service = QrTokenService();
    expect(service.checkInToken, isNotEmpty);
    expect(service.checkOutToken, isNot(service.checkInToken));
  });

  test('kindOf 는 각 토큰의 종류를 돌려준다', () {
    final service = QrTokenService();
    expect(service.kindOf(service.checkInToken), QrKind.checkIn);
    expect(service.kindOf(service.checkOutToken), QrKind.checkOut);
  });

  test('rotate 는 두 토큰을 모두 교체한다', () {
    final service = QrTokenService();
    final beforeCheckIn = service.checkInToken;
    final beforeCheckOut = service.checkOutToken;

    final rotatedAt = DateTime(2026, 10, 16, 12, 0, 0);
    service.rotate(now: rotatedAt);

    expect(service.checkInToken, isNot(beforeCheckIn));
    expect(service.checkOutToken, isNot(beforeCheckOut));
    // 현재 토큰도 수명이 있으므로 회전 시각 기준으로 판정한다.
    expect(
      service.kindOf(service.checkInToken, now: rotatedAt),
      QrKind.checkIn,
    );
    expect(
      service.kindOf(service.checkOutToken, now: rotatedAt),
      QrKind.checkOut,
    );
  });

  test('직전 토큰은 유예 창 안에서 종류를 유지한 채 유효하다', () {
    final service = QrTokenService(graceDuration: const Duration(seconds: 10));
    final firstCheckIn = service.checkInToken;
    final firstCheckOut = service.checkOutToken;
    final rotatedAt = DateTime(2026, 10, 16, 12, 0, 0);
    service.rotate(now: rotatedAt);

    expect(
      service.kindOf(
        firstCheckIn,
        now: rotatedAt.add(const Duration(seconds: 5)),
      ),
      QrKind.checkIn,
    );
    expect(
      service.kindOf(
        firstCheckOut,
        now: rotatedAt.add(const Duration(seconds: 5)),
      ),
      QrKind.checkOut,
    );
  });

  test('유예 창이 지나면 직전 토큰은 거부된다', () {
    final service = QrTokenService(graceDuration: const Duration(seconds: 10));
    final firstCheckIn = service.checkInToken;
    final rotatedAt = DateTime(2026, 10, 16, 12, 0, 0);
    service.rotate(now: rotatedAt);

    expect(
      service.kindOf(
        firstCheckIn,
        now: rotatedAt.add(const Duration(seconds: 11)),
      ),
      isNull,
    );
  });

  test('모르는 토큰은 null 이다', () {
    expect(QrTokenService().kindOf('not-a-real-token'), isNull);
  });

  test('회전이 멈추면 현재 토큰도 수명이 지나면 거부된다', () {
    final service = QrTokenService(
      validityDuration: const Duration(seconds: 30),
      graceDuration: const Duration(seconds: 10),
    );
    final rotatedAt = DateTime(2026, 10, 16, 12, 0, 0);
    service.rotate(now: rotatedAt);
    final token = service.checkInToken;

    expect(
      service.kindOf(token, now: rotatedAt.add(const Duration(seconds: 39))),
      QrKind.checkIn,
    );
    expect(
      service.kindOf(token, now: rotatedAt.add(const Duration(seconds: 41))),
      isNull,
    );
  });

  test('한 번도 회전하지 않은 서비스의 현재 토큰은 시간이 지나도 유효하다', () {
    final service = QrTokenService();
    final farFuture = DateTime.now().add(const Duration(days: 1));

    expect(
      service.kindOf(service.checkInToken, now: farFuture),
      QrKind.checkIn,
    );
    expect(
      service.kindOf(service.checkOutToken, now: farFuture),
      QrKind.checkOut,
    );
  });
}
