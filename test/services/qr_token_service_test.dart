import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/qr_token_service.dart';

void main() {
  test('회전하면 토큰 값이 바뀐다', () {
    final service = QrTokenService();
    final before = service.token;
    expect(before, isNotEmpty);

    final rotatedAt = DateTime(2026, 10, 27, 12, 0, 0);
    service.rotate(now: rotatedAt);

    expect(service.token, isNot(before));
    expect(service.isValid(service.token, now: rotatedAt), isTrue);
  });

  test('직전 토큰은 유예 창 안에서만 통한다', () {
    final service = QrTokenService(graceDuration: const Duration(seconds: 10));
    final first = service.token;
    final rotatedAt = DateTime(2026, 10, 27, 12, 0, 0);
    service.rotate(now: rotatedAt);

    expect(
      service.isValid(first, now: rotatedAt.add(const Duration(seconds: 5))),
      isTrue,
    );
    expect(
      service.isValid(first, now: rotatedAt.add(const Duration(seconds: 11))),
      isFalse,
    );
  });

  // 회전 타이머가 죽어도(핫 리로드, 콜백 예외) 촬영한 QR 이 영구히 통하면 안 된다.
  test('현재 토큰도 수명 + 유예가 지나면 거부한다', () {
    final service = QrTokenService(
      validityDuration: const Duration(seconds: 30),
      graceDuration: const Duration(seconds: 10),
    );
    final rotatedAt = DateTime(2026, 10, 27, 12, 0, 0);
    service.rotate(now: rotatedAt);
    final token = service.token;

    expect(
      service.isValid(token, now: rotatedAt.add(const Duration(seconds: 39))),
      isTrue,
    );
    expect(
      service.isValid(token, now: rotatedAt.add(const Duration(seconds: 41))),
      isFalse,
    );
  });

  test('현재 토큰의 수명 경계는 validity + grace 정각이다', () {
    final service = QrTokenService(
      validityDuration: const Duration(seconds: 30),
      graceDuration: const Duration(seconds: 10),
    );
    final rotatedAt = DateTime(2026, 10, 27, 12, 0, 0);
    service.rotate(now: rotatedAt);
    final token = service.token;

    expect(
      service.isValid(
        token,
        now: rotatedAt.add(const Duration(seconds: 40, milliseconds: -1)),
      ),
      isTrue,
    );
    expect(
      service.isValid(token, now: rotatedAt.add(const Duration(seconds: 40))),
      isFalse,
    );
  });

  test('한 번도 회전하지 않았으면 현재 토큰은 유효하다', () {
    final service = QrTokenService();
    final farFuture = DateTime.now().add(const Duration(days: 1));

    expect(service.isValid(service.token, now: farFuture), isTrue);
  });

  test('모르는 토큰은 거부한다', () {
    expect(QrTokenService().isValid('not-a-real-token'), isFalse);
  });
}
