import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

  Future<http.Response> check(
    String session, {
    String deviceToken = 'device-1',
  }) => post('/api/checkin', {'session': session, 'deviceToken': deviceToken});

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
    final session = await h.issueSession(h.qr.checkInToken);

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
      final session = await h.issueSession(h.qr.checkInToken);

      final response = await h.bind(
        session: session,
        memberId: memberId,
        contactLast4: '9999',
      );
      expect(response.statusCode, 403);
      expect(_body(response)['error'], 'verification_failed');
      expect(await h.devices.getByToken('device-1'), isNull);

      await h.close();
    },
  );

  test(
    'POST /api/bind 는 연락처가 없는 회원을 403 verification_unavailable 로 거부한다',
    () async {
      final h = await CheckInServerHarness.start();
      addTearDown(h.close);
      final memberId = await h.members.insert(const Member(name: '홍길동'));
      final session = await h.issueSession(h.qr.checkInToken);

      final response = await h.bind(
        session: session,
        memberId: memberId,
        contactLast4: '0000',
      );
      expect(response.statusCode, 403);
      expect(_body(response)['error'], 'verification_unavailable');
      expect(await h.devices.getByToken('device-1'), isNull);

      await h.close();
    },
  );

  test('POST /api/bind 는 연락처의 하이픈 유무와 무관하게 뒷 4자리를 판정한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', parentContact: '01011112222'),
    );
    final session = await h.issueSession(h.qr.checkInToken);

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
    final session = await h.issueSession(h.qr.checkInToken);

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

  test('POST /api/checkin 은 등원 세션으로 등원을 기록하고 알림을 낸다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    final session = await h.issueSession(h.qr.checkInToken);

    final response = await h.check(session);
    expect(response.statusCode, 200);
    expect(_body(response)['result'], 'checkedIn');
    expect(_body(response)['memberName'], '홍길동');
    expect(_body(response)['status'], 'present');

    final logs = await h.notificationLogs.getRecent();
    expect(logs, hasLength(1));
    expect(logs.single.kind, NotificationKind.checkIn);
  });

  test('POST /api/checkin 재스캔은 alreadyCheckedIn 이고 알림을 더 내지 않는다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();

    final first = await h.check(await h.issueSession(h.qr.checkInToken));
    expect(_body(first)['result'], 'checkedIn');

    final second = await h.check(await h.issueSession(h.qr.checkInToken));
    expect(second.statusCode, 200);
    expect(_body(second)['result'], 'alreadyCheckedIn');
    expect(_body(second)['memberName'], '홍길동');

    expect(await h.notificationLogs.getRecent(), hasLength(1));
  });

  test('POST /api/checkin 은 하원 세션으로 하원을 기록하고 알림을 낸다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    await h.check(await h.issueSession(h.qr.checkInToken));

    final response = await h.check(await h.issueSession(h.qr.checkOutToken));
    expect(response.statusCode, 200);
    expect(_body(response)['result'], 'checkedOut');
    expect(_body(response)['memberName'], '홍길동');

    final kinds = (await h.notificationLogs.getRecent()).map((l) => l.kind);
    expect(
      kinds,
      unorderedEquals([NotificationKind.checkIn, NotificationKind.checkOut]),
    );
  });

  test('POST /api/checkin 하원 재스캔은 alreadyCheckedOut 이고 알림을 더 내지 않는다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    await h.check(await h.issueSession(h.qr.checkInToken));
    await h.check(await h.issueSession(h.qr.checkOutToken));

    final rescan = await h.check(await h.issueSession(h.qr.checkOutToken));
    expect(rescan.statusCode, 200);
    expect(_body(rescan)['result'], 'alreadyCheckedOut');
    expect(_body(rescan)['memberName'], '홍길동');

    expect(await h.notificationLogs.getRecent(), hasLength(2));
  });

  test(
    'POST /api/checkin 은 등원 없이 하원하면 400 no_open_session 이고 알림을 내지 않는다',
    () async {
      final h = await CheckInServerHarness.start();
      addTearDown(h.close);
      await h.boundMember();
      final session = await h.issueSession(h.qr.checkOutToken);

      final response = await h.check(session);
      expect(response.statusCode, 400);
      expect(_body(response)['error'], 'no_open_session');
      expect(await h.notificationLogs.getRecent(), isEmpty);

      await h.close();
    },
  );

  test('POST /api/checkin 은 묶이지 않은 기기를 400 member_required 로 거부한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.members.insert(
      const Member(name: '홍길동', parentContact: '010-1111-2222'),
    );
    final session = await h.issueSession(h.qr.checkInToken);

    final response = await h.check(session, deviceToken: 'never-bound');
    expect(response.statusCode, 400);
    expect(_body(response)['error'], 'member_required');
    expect(await h.notificationLogs.getRecent(), isEmpty);
  });

  test('POST /api/checkin 은 세션 없이는 403 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();

    final response = await h.post('/api/checkin', {'deviceToken': 'device-1'});
    expect(response.statusCode, 403);
    expect(_body(response)['error'], 'invalid_session');
    expect(await h.notificationLogs.getRecent(), isEmpty);
  });

  test('체크에 쓴 세션은 소비되어 재사용할 수 없다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.boundMember();
    final session = await h.issueSession(h.qr.checkInToken);

    final first = await h.check(session);
    expect(first.statusCode, 200);

    final reused = await h.check(session);
    expect(reused.statusCode, 403);
    expect(_body(reused)['error'], 'invalid_session');
  });

  test('바인딩에 쓴 세션으로 이어서 체크할 수 있다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', parentContact: '010-1111-2222'),
    );
    final session = await h.issueSession(h.qr.checkInToken);

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
      final session = await h.issueSession(h.qr.checkInToken);

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
    final session = await h.issueSession(h.qr.checkInToken);

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
    final session = await h.issueSession(h.qr.checkInToken);

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
      {'session': session},
      {'session': session, 'deviceToken': 42},
      {'session': session, 'deviceToken': ''},
    ];
    for (final body in checkBodies) {
      final response = await h.post('/api/checkin', body);
      expect(response.statusCode, 400);
      expect(_body(response)['error'], 'bad_request');
    }

    // 잘못된 요청은 세션을 소모하지도, 기록을 남기지도 않는다.
    expect(await h.notificationLogs.getRecent(), isEmpty);
    expect((await h.check(session)).statusCode, 200);
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
