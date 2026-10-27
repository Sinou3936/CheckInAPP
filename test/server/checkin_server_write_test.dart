import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/notification_log.dart';

import '../helpers/checkin_server_harness.dart';

extension on CheckInServerHarness {
  Future<http.Response> post(String path, Object? body) => http.post(
    uri(path),
    headers: {'content-type': 'application/json'},
    body: jsonEncode(body),
  );

  Future<http.Response> bind({
    required String session,
    required int memberId,
    required String contactLast4,
    String deviceToken = 'device-1',
  }) => post('/api/bind', {
    'session': session,
    'deviceToken': deviceToken,
    'memberId': memberId,
    'contactLast4': contactLast4,
  });

  /// 판정을 읽어 그 세션이 발급한 action id 중 [kind] 짜리를 돌려준다.
  Future<String> actionId(
    String session, {
    String kind = 'checkIn',
    String deviceToken = 'device-1',
  }) async {
    final body = jsonDecode(
      (await nextAction(session, deviceToken: deviceToken)).body,
    ) as Map;
    final actions = (body['actions'] as List).cast<Map>();
    return actions.firstWhere((a) => a['kind'] == kind)['id'] as String;
  }

  /// 한 번의 스캔을 끝까지 흘린다: 판정을 읽고 그 action id 로 기록한다.
  Future<http.Response> check(
    String session, {
    String kind = 'checkIn',
    String deviceToken = 'device-1',
  }) async => post('/api/checkin', {
    'session': session,
    'deviceToken': deviceToken,
    'actionId': await actionId(session, kind: kind, deviceToken: deviceToken),
  });

  /// 새 세션으로 한 번 스캔한다.
  Future<http.Response> scan({String kind = 'checkIn'}) async =>
      check(await issueSession(), kind: kind);

  /// 연락처가 있는 회원을 만들고 `device-1` 을 그 회원에 묶어 둔다.
  Future<int> boundMember() async {
    final memberId = await members.insert(
      const Member(name: '홍길동', parentContact: '010-1111-2222'),
    );
    await devices.bind('device-1', memberId);
    return memberId;
  }
}

Map _body(http.Response response) => jsonDecode(response.body) as Map;

void main() {
  test('POST /api/bind 는 뒷 4자리가 맞으면 기기를 묶는다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', parentContact: '010-1111-2222'),
    );
    final session = await h.issueSession();

    final response = await h.bind(
      session: session,
      memberId: memberId,
      contactLast4: '2222',
    );
    expect(response.statusCode, 200);
    expect(response.headers['cache-control'], 'no-store');
    expect(_body(response)['bound'], isTrue);
    expect(_body(response)['memberName'], '홍길동');
    expect((await h.devices.getByToken('device-1'))!.memberId, memberId);
  });

  test(
    'POST /api/bind 는 뒷 4자리가 틀리면 403 verification_failed 이고 묶지 않는다',
    () async {
      final h = await CheckInServerHarness.start();
      addTearDown(h.close);
      final memberId = await h.members.insert(
        const Member(name: '홍길동', parentContact: '010-1111-2222'),
      );
      final session = await h.issueSession();

      final response = await h.bind(
        session: session,
        memberId: memberId,
        contactLast4: '9999',
      );
      expect(response.statusCode, 403);
      expect(_body(response)['error'], 'verification_failed');
      expect(await h.devices.getByToken('device-1'), isNull);
    },
  );

  test(
    'POST /api/bind 는 연락처가 없는 회원을 403 verification_unavailable 로 거부한다',
    () async {
      final h = await CheckInServerHarness.start();
      addTearDown(h.close);
      final memberId = await h.members.insert(const Member(name: '홍길동'));
      final session = await h.issueSession();

      final response = await h.bind(
        session: session,
        memberId: memberId,
        contactLast4: '0000',
      );
      expect(response.statusCode, 403);
      expect(_body(response)['error'], 'verification_unavailable');
      expect(await h.devices.getByToken('device-1'), isNull);
    },
  );

  test('POST /api/bind 는 연락처의 하이픈 유무와 무관하게 뒷 4자리를 판정한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', parentContact: '01011112222'),
    );
    final session = await h.issueSession();

    final response = await h.bind(
      session: session,
      memberId: memberId,
      contactLast4: '2222',
    );
    expect(response.statusCode, 200);
    expect((await h.devices.getByToken('device-1'))!.memberId, memberId);
  });

  test('POST /api/bind 는 연속 5회 실패 뒤 429 를 돌려준다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', parentContact: '010-1111-2222'),
    );
    final session = await h.issueSession();

    for (var i = 0; i < 5; i++) {
      final wrong = await h.bind(
        session: session,
        memberId: memberId,
        contactLast4: '000$i',
      );
      expect(wrong.statusCode, 403);
      expect(_body(wrong)['error'], 'verification_failed');
    }

    final wrongAgain = await h.bind(
      session: session,
      memberId: memberId,
      contactLast4: '9999',
    );
    expect(wrongAgain.statusCode, 429);
    expect(_body(wrongAgain)['error'], 'too_many_attempts');

    // 올바른 4자리를 보내도 잠긴 동안에는 통과하지 못한다 — 아니면 차단이 의미가 없다.
    final correct = await h.bind(
      session: session,
      memberId: memberId,
      contactLast4: '2222',
    );
    expect(correct.statusCode, 429);
    expect(await h.devices.getByToken('device-1'), isNull);
  });

  test('POST /api/bind 는 세션 없이는 403 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', parentContact: '010-1111-2222'),
    );

    final response = await h.post('/api/bind', {
      'deviceToken': 'device-1',
      'memberId': memberId,
      'contactLast4': '2222',
    });
    expect(response.statusCode, 403);
    expect(_body(response)['error'], 'invalid_session');
    expect(await h.devices.getByToken('device-1'), isNull);
  });

  test('POST /api/checkin 은 등원 action 으로 등원을 기록하고 알림을 낸다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();

    final response = await h.scan();
    expect(response.statusCode, 200);
    expect(_body(response)['result'], 'checkedIn');
    expect(_body(response)['memberName'], '홍길동');
    expect(_body(response)['status'], 'present');

    final logs = await h.notificationLogs.getRecent();
    expect(logs, hasLength(1));
    expect(logs.single.kind, NotificationKind.checkIn);
  });

  test('POST /api/checkin 은 하원 action 으로 하원을 기록하고 알림을 낸다', () async {
    final now = DateTime(2026, 10, 27, 18, 0);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    final memberId = await h.boundMember();
    await h.attendance.insert(
      Attendance(
        memberId: memberId,
        date: '2026-10-27',
        checkInTime: DateTime(2026, 10, 27, 15, 0).toIso8601String(),
        status: AttendanceStatus.present,
      ),
    );

    final response = await h.scan(kind: 'checkOut');
    expect(response.statusCode, 200);
    expect(_body(response)['result'], 'checkedOut');
    expect(_body(response)['memberName'], '홍길동');

    final logs = await h.notificationLogs.getRecent();
    expect(logs.single.kind, NotificationKind.checkOut);
  });

  // 최소 체류 시간을 넘긴 뒤의 재스캔이다. 등원 직후의 재스캔은 판정이 차단하므로 여기에
  // 오지 않는다.
  test('하원 뒤 같은 날 다시 스캔하면 판정이 완료이고 action 이 없다', () async {
    final now = DateTime(2026, 10, 27, 18, 5);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    final memberId = await h.boundMember();
    await h.attendance.insert(
      Attendance(
        memberId: memberId,
        date: '2026-10-27',
        checkInTime: DateTime(2026, 10, 27, 15, 0).toIso8601String(),
        checkOutTime: DateTime(2026, 10, 27, 18, 0).toIso8601String(),
        status: AttendanceStatus.present,
      ),
    );

    final body =
        jsonDecode((await h.nextAction(await h.issueSession())).body) as Map;
    expect(body['action'], 'alreadyCheckedOut');
    expect(body['actions'], isEmpty);
    expect(await h.notificationLogs.getRecent(), isEmpty);
  });

  test('POST /api/checkin 은 묶이지 않은 기기를 400 member_required 로 거부한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    final session = await h.issueSession();
    final actionId = await h.actionId(session);

    final response = await h.post('/api/checkin', {
      'session': session,
      'deviceToken': 'never-bound',
      'actionId': actionId,
    });
    expect(response.statusCode, 400);
    expect(_body(response)['error'], 'member_required');
    expect(await h.notificationLogs.getRecent(), isEmpty);
  });

  test('POST /api/checkin 은 세션 없이는 403 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();

    final response = await h.post('/api/checkin', {
      'deviceToken': 'device-1',
      'actionId': 'whatever',
    });
    expect(response.statusCode, 403);
    expect(_body(response)['error'], 'invalid_session');
    expect(await h.notificationLogs.getRecent(), isEmpty);
  });

  test('POST /api/checkin 은 actionId 가 없으면 400 bad_request 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    final session = await h.issueSession();

    for (final actionId in <Object?>[null, 42, '']) {
      final response = await h.post('/api/checkin', {
        'session': session,
        'deviceToken': 'device-1',
        'actionId': ?actionId,
      });
      expect(response.statusCode, 400, reason: 'actionId: $actionId');
      expect(_body(response)['error'], 'bad_request');
    }
    expect(await h.notificationLogs.getRecent(), isEmpty);
  });

  // 위조 방지. id 를 세션에서 떼어낼 수 있으면 남의 세션에서 받은 id 로 기록을 만들 수 있다.
  test('다른 세션의 action id 는 403 invalid_action 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    final other = await h.issueSession();
    final stolen = await h.actionId(other);
    final mine = await h.issueSession();

    final response = await h.post('/api/checkin', {
      'session': mine,
      'deviceToken': 'device-1',
      'actionId': stolen,
    });
    expect(response.statusCode, 403);
    expect(_body(response)['error'], 'invalid_action');
    expect(await h.notificationLogs.getRecent(), isEmpty);
  });

  // 같은 id 로 두 번 기록되면 학부모에게 알림이 두 번 간다.
  test('같은 action id 로 두 번 쓰면 두 번째는 거부되고 알림은 한 번만 간다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    final session = await h.issueSession();
    final actionId = await h.actionId(session);

    final first = await h.post('/api/checkin', {
      'session': session,
      'deviceToken': 'device-1',
      'actionId': actionId,
    });
    expect(first.statusCode, 200);

    final second = await h.post('/api/checkin', {
      'session': session,
      'deviceToken': 'device-1',
      'actionId': actionId,
    });
    expect(second.statusCode, 403);
    expect(_body(second)['error'], 'invalid_session');
    expect(await h.notificationLogs.getRecent(), hasLength(1));
  });

  // 위조 방지. 종류를 문자열로 받으면 학생이 그 값만 바꿔 하원을 만들 수 있다.
  test('본문의 kind 는 무시되고 action id 가 정한 것이 기록된다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    final session = await h.issueSession();

    final response = await h.post('/api/checkin', {
      'session': session,
      'deviceToken': 'device-1',
      'actionId': await h.actionId(session),
      'kind': 'checkOut',
    });
    expect(response.statusCode, 200);
    expect(_body(response)['result'], 'checkedIn');
    expect(
      (await h.notificationLogs.getRecent()).single.kind,
      NotificationKind.checkIn,
    );
  });

  // 확인 화면이 뜬 뒤 관리자 보정으로 상태가 바뀌는 경로가 실제로 있다.
  test('판정이 바뀌면 기록하지 않고 409 state_changed 와 새 판정을 준다', () async {
    final now = DateTime(2026, 10, 27, 15, 12);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    final memberId = await h.boundMember();
    final session = await h.issueSession();
    // 아직 기록이 없으니 등원 판정이고 action id 도 등원이다.
    final actionId = await h.actionId(session);

    // 그 사이 관리자가 15:00 등원을 심었다 (또는 다른 기기가 먼저 찍었다).
    await h.attendance.insert(
      Attendance(
        memberId: memberId,
        date: '2026-10-27',
        checkInTime: DateTime(2026, 10, 27, 15, 0).toIso8601String(),
        status: AttendanceStatus.present,
      ),
    );

    final response = await h.post('/api/checkin', {
      'session': session,
      'deviceToken': 'device-1',
      'actionId': actionId,
    });
    expect(response.statusCode, 409);
    final body = _body(response);
    expect(body['error'], 'state_changed');
    // 페이지가 재확인 화면을 그릴 수 있도록 읽기 응답과 같은 모양으로 온다.
    expect(body['action'], 'tooEarly');
    expect(body['remainingMinutes'], 18);
    expect(body['memberName'], '홍길동');
    expect(await h.notificationLogs.getRecent(), isEmpty);
  });

  test('날짜 경계의 선택에서 하원을 고르면 어제 행이 닫히고 오늘 행은 생기지 않는다', () async {
    final now = DateTime(2026, 10, 27, 8, 0);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    final memberId = await h.boundMember();
    await h.attendance.insert(
      Attendance(
        memberId: memberId,
        date: '2026-10-26',
        checkInTime: DateTime(2026, 10, 26, 23, 50).toIso8601String(),
        status: AttendanceStatus.present,
      ),
    );

    final response = await h.scan(kind: 'checkOut');
    expect(_body(response)['result'], 'checkedOut');

    final yesterday = await h.attendance.getByMemberAndDate(
      memberId,
      '2026-10-26',
    );
    expect(yesterday!.checkOutTime, isNotNull);
    expect(
      await h.attendance.getByMemberAndDate(memberId, '2026-10-27'),
      isNull,
    );
  });

  test('날짜 경계의 선택에서 등원을 고르면 오늘 행이 생기고 어제 행은 열린 채 남는다', () async {
    final now = DateTime(2026, 10, 27, 8, 0);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    final memberId = await h.boundMember();
    await h.attendance.insert(
      Attendance(
        memberId: memberId,
        date: '2026-10-26',
        checkInTime: DateTime(2026, 10, 26, 23, 50).toIso8601String(),
        status: AttendanceStatus.present,
      ),
    );

    final response = await h.scan(kind: 'checkIn');
    expect(_body(response)['result'], 'checkedIn');

    final today = await h.attendance.getByMemberAndDate(memberId, '2026-10-27');
    expect(today!.checkInTime, contains('08:00'));
    final yesterday = await h.attendance.getByMemberAndDate(
      memberId,
      '2026-10-26',
    );
    // 언제 나갔는지 모르므로 하원 시각을 꾸며 넣지 않는다. 관리자 보정 대상이다.
    expect(yesterday!.checkOutTime, isNull);
    expect(
      (await h.notificationLogs.getRecent()).single.kind,
      NotificationKind.checkIn,
    );
  });

  test('체크에 쓴 세션은 소비되어 재사용할 수 없다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    final session = await h.issueSession();

    final first = await h.check(session);
    expect(first.statusCode, 200);

    final reused = await h.nextAction(session);
    expect(reused.statusCode, 403);
    expect(_body(reused)['error'], 'invalid_session');
  });

  test('바인딩에 쓴 세션으로 이어서 체크할 수 있다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', parentContact: '010-1111-2222'),
    );
    final session = await h.issueSession();

    final bound = await h.bind(
      session: session,
      memberId: memberId,
      contactLast4: '2222',
    );
    expect(bound.statusCode, 200);

    final checked = await h.check(session);
    expect(checked.statusCode, 200);
    expect(_body(checked)['result'], 'checkedIn');
  });

  test(
    'POST /api/bind 는 연락처가 빈 문자열이거나 4자리 미만이면 403 verification_unavailable 이다',
    () async {
      final h = await CheckInServerHarness.start();
      addTearDown(h.close);
      final session = await h.issueSession();

      // 빈 연락처가 빈 값과 비교되어 아무 입력으로나 통과하면 본인 확인이 무너진다.
      for (final contact in ['', '12']) {
        final memberId = await h.members.insert(
          Member(name: '홍길동', parentContact: contact),
        );
        for (final input in ['', '12', '0000']) {
          final response = await h.bind(
            session: session,
            memberId: memberId,
            contactLast4: input,
          );
          expect(
            response.statusCode,
            403,
            reason: '연락처 "$contact" 입력 "$input"',
          );
          expect(_body(response)['error'], 'verification_unavailable');
        }
      }
      expect(await h.devices.getByToken('device-1'), isNull);
    },
  );

  test('POST /api/bind 는 기기 토큰을 바꿔가며 같은 회원을 5회 틀려도 429 를 돌려준다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', parentContact: '010-1111-2222'),
    );
    final session = await h.issueSession();

    for (var i = 0; i < 5; i++) {
      final wrong = await h.bind(
        session: session,
        memberId: memberId,
        contactLast4: '000$i',
        deviceToken: 'fresh-$i',
      );
      expect(wrong.statusCode, 403);
    }

    // 6번째는 새 기기 토큰에 올바른 4자리여도 막힌다.
    final correct = await h.bind(
      session: session,
      memberId: memberId,
      contactLast4: '2222',
      deviceToken: 'fresh-new',
    );
    expect(correct.statusCode, 429);
    expect(_body(correct)['error'], 'too_many_attempts');
    expect(await h.devices.getByToken('fresh-new'), isNull);
  });

  test('POST /api/bind 와 /api/checkin 은 deviceToken 이 없거나 문자열이 아니면 400 bad_request 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.boundMember();
    final session = await h.issueSession();
    final actionId = await h.actionId(session);

    final bindBodies = <Map<String, Object?>>[
      {'session': session, 'memberId': memberId, 'contactLast4': '2222'},
      {
        'session': session,
        'deviceToken': 42,
        'memberId': memberId,
        'contactLast4': '2222',
      },
    ];
    for (final body in bindBodies) {
      final response = await h.post('/api/bind', body);
      expect(response.statusCode, 400);
      expect(_body(response)['error'], 'bad_request');
    }

    final checkBodies = <Map<String, Object?>>[
      {'session': session, 'actionId': actionId},
      {'session': session, 'deviceToken': 42, 'actionId': actionId},
      {'session': session, 'deviceToken': '', 'actionId': actionId},
    ];
    for (final body in checkBodies) {
      final response = await h.post('/api/checkin', body);
      expect(response.statusCode, 400);
      expect(_body(response)['error'], 'bad_request');
    }

    // 잘못된 요청은 세션을 소모하지도, 기록을 남기지도 않는다.
    expect(await h.notificationLogs.getRecent(), isEmpty);
    final ok = await h.post('/api/checkin', {
      'session': session,
      'deviceToken': 'device-1',
      'actionId': actionId,
    });
    expect(ok.statusCode, 200);
  });

  test(
    'POST /api/bind 와 /api/checkin 은 JSON 객체가 아닌 본문을 400 bad_request 로 거부한다',
    () async {
      final h = await CheckInServerHarness.start();
      addTearDown(h.close);

      for (final path in ['/api/bind', '/api/checkin']) {
        for (final body in <Object?>[<Object?>[], 'text']) {
          final response = await h.post(path, body);
          expect(response.statusCode, 400, reason: '$path $body');
          expect(_body(response)['error'], 'bad_request');
        }
        final malformed = await http.post(h.uri(path), body: '{not json');
        expect(malformed.statusCode, 400);
        expect(_body(malformed)['error'], 'bad_request');
      }
    },
  );
}
