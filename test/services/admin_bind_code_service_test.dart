import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/admin_bind_code_service.dart';

void main() {
  test('발급한 코드는 6자리 숫자이고 한 번만 쓸 수 있다', () {
    final service = AdminBindCodeService();
    final code = service.issue(1);

    expect(code, matches(RegExp(r'^[0-9]{6}$')));
    expect(service.consume(1, code), isTrue);
    expect(service.consume(1, code), isFalse);
  });

  test('틀린 코드는 거부하고 맞는 코드를 소비하지 않는다', () {
    final service = AdminBindCodeService();
    final code = service.issue(1);
    final wrong = code == '000000' ? '000001' : '000000';

    expect(service.consume(1, wrong), isFalse);
    expect(service.consume(1, code), isTrue);
  });

  test('다른 회원의 코드로는 통과하지 못한다', () {
    final service = AdminBindCodeService();
    final code = service.issue(1);

    expect(service.consume(2, code), isFalse);
  });

  test('새로 발급하면 이전 코드는 무효가 된다', () {
    final service = AdminBindCodeService();
    final first = service.issue(1);
    final second = service.issue(1);

    if (first != second) expect(service.consume(1, first), isFalse);
    expect(service.consume(1, second), isTrue);
  });

  test('수명이 지난 코드는 거부한다', () {
    final service = AdminBindCodeService(ttl: const Duration(minutes: 5));
    final issuedAt = DateTime(2026, 10, 26, 10, 0);
    final code = service.issue(1, now: issuedAt);

    expect(
      service.consume(1, code, now: issuedAt.add(const Duration(minutes: 5))),
      isFalse,
    );
  });
}
