import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/services/verification_session_service.dart';

void main() {
  test('발급한 세션은 종류를 돌려준다', () {
    final service = VerificationSessionService();
    final id = service.issue(QrKind.checkOut);
    expect(id, isNotEmpty);
    expect(service.kindOf(id), QrKind.checkOut);
  });

  test('ttl 이 지난 세션은 거부된다', () {
    final service = VerificationSessionService(ttl: const Duration(minutes: 5));
    final issuedAt = DateTime(2026, 10, 16, 12, 0, 0);
    final id = service.issue(QrKind.checkIn, now: issuedAt);

    expect(
      service.kindOf(id, now: issuedAt.add(const Duration(minutes: 4))),
      QrKind.checkIn,
    );
    expect(
      service.kindOf(id, now: issuedAt.add(const Duration(minutes: 6))),
      isNull,
    );
  });

  test('consume 한 세션은 다시 쓸 수 없다', () {
    final service = VerificationSessionService();
    final id = service.issue(QrKind.checkIn);
    service.consume(id);
    expect(service.kindOf(id), isNull);
  });

  test('모르는 세션은 null 이다', () {
    expect(VerificationSessionService().kindOf('nope'), isNull);
  });
}
