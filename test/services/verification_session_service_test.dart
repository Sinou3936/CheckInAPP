import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/check_kind.dart';
import 'package:checkin_app/services/verification_session_service.dart';

void main() {
  test('발급한 세션은 유효하다', () {
    final service = VerificationSessionService();
    final id = service.issue();
    expect(id, isNotEmpty);
    expect(service.isValid(id), isTrue);
  });

  test('ttl 이 지난 세션은 거부된다', () {
    final service = VerificationSessionService(ttl: const Duration(minutes: 5));
    final issuedAt = DateTime(2026, 10, 27, 12, 0, 0);
    final id = service.issue(now: issuedAt);

    expect(
      service.isValid(id, now: issuedAt.add(const Duration(minutes: 4))),
      isTrue,
    );
    expect(
      service.isValid(id, now: issuedAt.add(const Duration(minutes: 6))),
      isFalse,
    );
  });

  test('consume 한 세션은 다시 쓸 수 없다', () {
    final service = VerificationSessionService();
    final id = service.issue();
    service.consume(id);
    expect(service.isValid(id), isFalse);
  });

  test('모르는 세션은 유효하지 않다', () {
    expect(VerificationSessionService().isValid('nope'), isFalse);
  });

  test('등록한 행동을 그 세션에서 되찾는다', () {
    final service = VerificationSessionService();
    final session = service.issue();

    final actionId = service.registerAction(session, CheckKind.checkOut)!;

    expect(actionId, isNotEmpty);
    expect(service.actionOf(session, actionId), CheckKind.checkOut);
  });

  // 판정 8번(날짜 경계의 선택)에서 서버가 두 행동을 함께 내준다.
  test('두 행동을 등록하면 서로 다른 id 가 나온다', () {
    final service = VerificationSessionService();
    final session = service.issue();

    final out = service.registerAction(session, CheckKind.checkOut)!;
    final into = service.registerAction(session, CheckKind.checkIn)!;

    expect(out, isNot(into));
    expect(service.actionOf(session, out), CheckKind.checkOut);
    expect(service.actionOf(session, into), CheckKind.checkIn);
  });

  // action id 를 세션에서 떼어내면 남의 세션으로 하원을 만들 수 있다.
  test('다른 세션의 action id 는 통하지 않는다', () {
    final service = VerificationSessionService();
    final a = service.issue();
    final b = service.issue();

    final actionId = service.registerAction(a, CheckKind.checkOut)!;

    expect(service.actionOf(b, actionId), isNull);
  });

  test('consume 뒤에는 그 세션의 action id 도 통하지 않는다', () {
    final service = VerificationSessionService();
    final session = service.issue();
    final actionId = service.registerAction(session, CheckKind.checkIn)!;

    service.consume(session);

    expect(service.actionOf(session, actionId), isNull);
  });

  test('ttl 이 지난 세션의 action id 는 통하지 않는다', () {
    final service = VerificationSessionService(ttl: const Duration(minutes: 5));
    final issuedAt = DateTime(2026, 10, 27, 12, 0, 0);
    final session = service.issue(now: issuedAt);
    final actionId = service.registerAction(
      session,
      CheckKind.checkIn,
      now: issuedAt,
    )!;

    expect(
      service.actionOf(
        session,
        actionId,
        now: issuedAt.add(const Duration(minutes: 6)),
      ),
      isNull,
    );
  });

  test('무효한 세션에는 행동을 등록할 수 없다', () {
    final service = VerificationSessionService();

    expect(service.registerAction('nope', CheckKind.checkIn), isNull);
  });

  test('모르는 action id 는 통하지 않는다', () {
    final service = VerificationSessionService();
    final session = service.issue();

    expect(service.actionOf(session, 'nope'), isNull);
  });
}
