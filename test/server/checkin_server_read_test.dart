import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/services/checkin_event_bus.dart';

import '../helpers/checkin_server_harness.dart';

Map _body(http.Response response) => jsonDecode(response.body) as Map;

/// 오늘 날짜의 열린 세션 하나를 심는다. [checkInTime] 은 [now] 기준의 실제 시각이다.
Future<int> seedOpenSession(
  CheckInServerHarness h, {
  required DateTime now,
  required DateTime checkInTime,
  DateTime? checkOutTime,
}) async {
  final memberId = await h.members.insert(const Member(name: '홍길동'));
  await h.devices.bind('device-1', memberId);
  await h.attendance.insert(
    Attendance(
      memberId: memberId,
      date:
          '${checkInTime.year.toString().padLeft(4, '0')}-'
          '${checkInTime.month.toString().padLeft(2, '0')}-'
          '${checkInTime.day.toString().padLeft(2, '0')}',
      checkInTime: checkInTime.toIso8601String(),
      checkOutTime: checkOutTime?.toIso8601String(),
      status: AttendanceStatus.present,
    ),
  );
  return memberId;
}

void main() {
  test('GET /api/session 은 세션만 발급하고 종류를 돌려주지 않는다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(h.uri('/api/session?token=${h.qr.token}'));
    expect(response.statusCode, 200);
    final body = _body(response);
    expect(body['sessionId'], isNotEmpty);
    // QR 이 하나이므로 담을 종류가 없다. 종류를 내주면 페이지가 그것을 믿고 보낸다.
    expect(body.containsKey('kind'), isFalse);
  });

  test('GET /api/session 은 모르는 토큰을 403 으로 거부한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(h.uri('/api/session?token=nope'));
    expect(response.statusCode, 403);
    expect(_body(response)['error'], 'invalid_token');
  });

  test('GET /api/members 는 세션 없이는 403 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(h.uri('/api/members'));
    expect(response.statusCode, 403);
    expect(_body(response)['error'], 'invalid_session');
  });

  test('GET /api/members 는 유효한 세션으로 명단을 돌려준다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.members.insert(const Member(name: '홍길동', classId: null));
    final session = await h.issueSession();

    final response = await http.get(h.uri('/api/members?session=$session'));
    expect(response.statusCode, 200);
    expect((jsonDecode(response.body) as List).single['name'], '홍길동');
  });

  test('GET /api/device-status 는 미바인딩 기기와 바인딩된 기기를 구분한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );
    await h.devices.bind('device-1', memberId);
    final session = await h.issueSession();

    final unbound = await http.get(
      h.uri('/api/device-status?deviceToken=unknown&session=$session'),
    );
    expect(unbound.statusCode, 200);
    expect(_body(unbound)['bound'], isFalse);

    final bound = await http.get(
      h.uri('/api/device-status?deviceToken=device-1&session=$session'),
    );
    expect(bound.statusCode, 200);
    expect(_body(bound)['bound'], isTrue);
    expect(_body(bound)['memberId'], memberId);
    expect(_body(bound)['memberName'], '홍길동');
  });

  test('확인 세션은 QR 이 갱신된 뒤에도 유효하다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.members.insert(const Member(name: '홍길동', classId: null));
    final staleToken = h.qr.token;
    final session = await h.issueSession(staleToken);

    // 최초 1회 절차는 30초를 넘기므로, 제출 시점에는 QR 이 이미 두 번 돌아 있다.
    h.qr.rotate();
    h.qr.rotate();

    final members = await http.get(h.uri('/api/members?session=$session'));
    expect(members.statusCode, 200);
    expect((jsonDecode(members.body) as List).single['name'], '홍길동');

    // 반면 그 사이 죽은 토큰으로는 새 세션을 받을 수 없다.
    final refused = await http.get(h.uri('/api/session?token=$staleToken'));
    expect(refused.statusCode, 403);
  });

  test('GET /api/device-status 는 회원이 삭제된 바인딩을 미바인딩으로 본다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );
    await h.devices.bind('device-1', memberId);
    await h.members.delete(memberId);
    final session = await h.issueSession();

    final response = await http.get(
      h.uri('/api/device-status?deviceToken=device-1&session=$session'),
    );
    expect(response.statusCode, 200);
    expect(_body(response)['bound'], isFalse, reason: '"null 님"으로 렌더되면 안 된다');
    expect(_body(response)['memberName'], isNull);
  });

  test('GET /api/device-status 는 세션 없이는 403 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(
      h.uri('/api/device-status?deviceToken=device-1'),
    );
    expect(response.statusCode, 403);
    expect(_body(response)['error'], 'invalid_session');
  });

  test('start 를 두 번 불러도 같은 포트를 돌려주고 리스너가 새지 않는다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final secondPort = await h.server.start(port: 0);
    expect(secondPort, h.port);
    expect((await http.get(h.uri('/checkin'))).statusCode, 200);

    // 리스너가 하나 새었다면 stop 한 뒤에도 먼저 뜬 쪽이 접속을 받는다.
    await h.server.stop();
    await expectLater(http.get(h.uri('/checkin')), throwsA(anything));
  });

  // --- 판정 읽기 경로 ---

  test('GET /api/next-action 은 세션 없이는 403 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(
      h.uri('/api/next-action?deviceToken=device-1'),
    );
    expect(response.statusCode, 403);
    expect(_body(response)['error'], 'invalid_session');
  });

  test(
    'GET /api/next-action 은 묶이지 않은 기기를 400 member_required 로 거부한다',
    () async {
      final h = await CheckInServerHarness.start();
      addTearDown(h.close);
      final session = await h.issueSession();

      final response = await h.nextAction(session, deviceToken: 'never-bound');
      expect(response.statusCode, 400);
      expect(_body(response)['error'], 'member_required');
    },
  );

  test('GET /api/next-action 은 기록이 없으면 등원 판정과 action id 하나를 준다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.devices.bind('device-1', memberId);
    final session = await h.issueSession();

    final response = await h.nextAction(session);
    expect(response.statusCode, 200);
    final body = _body(response);
    expect(body['action'], 'checkIn');
    expect(body['memberName'], '홍길동');
    final actions = body['actions'] as List;
    expect(actions, hasLength(1));
    expect((actions.single as Map)['kind'], 'checkIn');
    expect((actions.single as Map)['id'], isNotEmpty);
  });

  test('GET /api/next-action 은 체류 중이면 하원 판정을 준다', () async {
    final now = DateTime(2026, 10, 27, 18, 0);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    await seedOpenSession(
      h,
      now: now,
      checkInTime: DateTime(2026, 10, 27, 15, 0),
    );
    final session = await h.issueSession();

    final body = _body(await h.nextAction(session));
    expect(body['action'], 'checkOut');
    expect(((body['actions'] as List).single as Map)['kind'], 'checkOut');
    expect((body['openSession'] as Map)['date'], '2026-10-27');
  });

  // 판정 8번. 선택지의 집합은 서버가 정하고, 하원이 먼저 온다.
  test('GET /api/next-action 은 날짜 경계에서 action 을 둘 주고 하원이 먼저다', () async {
    final now = DateTime(2026, 10, 27, 8, 0);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    await seedOpenSession(
      h,
      now: now,
      checkInTime: DateTime(2026, 10, 26, 23, 50),
    );
    final session = await h.issueSession();

    final body = _body(await h.nextAction(session));
    expect(body['action'], 'choice');
    final actions = body['actions'] as List;
    expect(actions, hasLength(2));
    expect((actions.first as Map)['kind'], 'checkOut');
    expect((actions.last as Map)['kind'], 'checkIn');
    expect((body['openSession'] as Map)['date'], '2026-10-26');
    expect((body['openSession'] as Map)['checkInTime'], '23:50');
  });

  test('GET /api/next-action 은 차단이면 남은 분을 주고 action 을 주지 않는다', () async {
    final now = DateTime(2026, 10, 27, 15, 12);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    await seedOpenSession(
      h,
      now: now,
      checkInTime: DateTime(2026, 10, 27, 15, 0),
    );
    final session = await h.issueSession();

    final body = _body(await h.nextAction(session));
    expect(body['action'], 'tooEarly');
    expect(body['remainingMinutes'], 18);
    expect(body['actions'], isEmpty);
  });

  test('GET /api/next-action 은 하원 창을 넘기면 창 지남을 준다', () async {
    final now = DateTime(2026, 10, 27, 15, 0);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    await seedOpenSession(
      h,
      now: now,
      checkInTime: DateTime(2026, 10, 27, 2, 0),
    );
    final session = await h.issueSession();

    final body = _body(await h.nextAction(session));
    expect(body['action'], 'overdue');
    expect(body['actions'], isEmpty);
  });

  test('GET /api/next-action 은 이미 하원했으면 완료를 준다', () async {
    final now = DateTime(2026, 10, 27, 18, 5);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    await seedOpenSession(
      h,
      now: now,
      checkInTime: DateTime(2026, 10, 27, 15, 0),
      checkOutTime: DateTime(2026, 10, 27, 18, 0),
    );
    final session = await h.issueSession();

    final body = _body(await h.nextAction(session));
    expect(body['action'], 'alreadyCheckedOut');
    expect(body['actions'], isEmpty);
  });

  // 차단은 아무것도 기록하지 않으므로 이 배너가 유일한 흔적이다. 이것이 없으면 관리자는
  // 그 학생이 12시간 뒤 미하원으로 뜰 때까지 모른다.
  test('차단과 창 지남은 카운터에 배너 이벤트를 발행한다', () async {
    final tooEarlyNow = DateTime(2026, 10, 27, 15, 12);
    final h = await CheckInServerHarness.start(clock: () => tooEarlyNow);
    addTearDown(h.close);
    await seedOpenSession(
      h,
      now: tooEarlyNow,
      checkInTime: DateTime(2026, 10, 27, 15, 0),
    );

    final received = h.eventBus.events.first;
    await h.nextAction(await h.issueSession());

    final event = await received;
    expect(event.kind, CheckEventKind.blockedTooEarly);
    expect(event.memberName, '홍길동');
    expect(event.remaining, const Duration(minutes: 18));
  });

  test('창 지남은 blockedOverdue 로 발행한다', () async {
    final now = DateTime(2026, 10, 27, 15, 0);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    await seedOpenSession(
      h,
      now: now,
      checkInTime: DateTime(2026, 10, 27, 2, 0),
    );

    final received = h.eventBus.events.first;
    await h.nextAction(await h.issueSession());

    expect((await received).kind, CheckEventKind.blockedOverdue);
  });

  test('판정만 읽어도 아무것도 기록하지 않고 알림도 내지 않는다', () async {
    final now = DateTime(2026, 10, 27, 15, 12);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    final memberId = await seedOpenSession(
      h,
      now: now,
      checkInTime: DateTime(2026, 10, 27, 15, 0),
    );

    await h.nextAction(await h.issueSession());

    final stored = await h.attendance.getByMemberAndDate(
      memberId,
      '2026-10-27',
    );
    expect(stored!.checkOutTime, isNull);
    expect(await h.notificationLogs.getRecent(), isEmpty);
  });

  test('설정을 바꾸면 다음 요청이 새 값을 쓴다', () async {
    final now = DateTime(2026, 10, 27, 15, 12);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    await seedOpenSession(
      h,
      now: now,
      checkInTime: DateTime(2026, 10, 27, 15, 0),
    );

    // 기본값 30분에서는 12분 경과가 차단이다.
    expect(
      _body(await h.nextAction(await h.issueSession()))['action'],
      'tooEarly',
    );

    await h.minimumStay.write(const Duration(minutes: 5));

    // 앱을 다시 띄우지 않고 그 다음 요청부터 바뀐다.
    expect(
      _body(await h.nextAction(await h.issueSession()))['action'],
      'checkOut',
    );
  });
}
