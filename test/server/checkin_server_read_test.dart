import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/models/member.dart';

import '../helpers/checkin_server_harness.dart';

void main() {
  test('GET /api/session 은 등원 토큰에 checkIn 세션을 발급한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(
      h.uri('/api/session?token=${h.qr.checkInToken}'),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map;
    expect(body['kind'], 'checkIn');
    expect(body['sessionId'], isNotEmpty);
  });

  test('GET /api/session 은 하원 토큰에 checkOut 세션을 발급한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(
      h.uri('/api/session?token=${h.qr.checkOutToken}'),
    );
    expect(response.statusCode, 200);
    expect((jsonDecode(response.body) as Map)['kind'], 'checkOut');
  });

  test('GET /api/session 은 모르는 토큰을 403 으로 거부한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(h.uri('/api/session?token=nope'));
    expect(response.statusCode, 403);
    expect((jsonDecode(response.body) as Map)['error'], 'invalid_token');
  });

  test('GET /api/members 는 세션 없이는 403 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(h.uri('/api/members'));
    expect(response.statusCode, 403);
    expect((jsonDecode(response.body) as Map)['error'], 'invalid_session');
  });

  test('GET /api/members 는 유효한 세션으로 명단을 돌려준다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.members.insert(const Member(name: '홍길동', classId: null));
    final session = await h.issueSession(h.qr.checkInToken);

    final response = await http.get(h.uri('/api/members?session=$session'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as List;
    expect(body.single['name'], '홍길동');
  });

  test('GET /api/device-status 는 미바인딩 기기와 바인딩된 기기를 구분한다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );
    await h.devices.bind('device-1', memberId);
    final session = await h.issueSession(h.qr.checkInToken);

    final unbound = await http.get(
      h.uri('/api/device-status?deviceToken=unknown&session=$session'),
    );
    expect(unbound.statusCode, 200);
    expect((jsonDecode(unbound.body) as Map)['bound'], isFalse);

    final bound = await http.get(
      h.uri('/api/device-status?deviceToken=device-1&session=$session'),
    );
    expect(bound.statusCode, 200);
    final boundBody = jsonDecode(bound.body) as Map;
    expect(boundBody['bound'], isTrue);
    expect(boundBody['memberId'], memberId);
    expect(boundBody['memberName'], '홍길동');
  });

  test('확인 세션은 QR 이 갱신된 뒤에도 유효하다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await h.members.insert(const Member(name: '홍길동', classId: null));
    final staleToken = h.qr.checkInToken;
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
    final session = await h.issueSession(h.qr.checkInToken);

    final response = await http.get(
      h.uri('/api/device-status?deviceToken=device-1&session=$session'),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map;
    expect(body['bound'], isFalse, reason: '"null 님"으로 렌더되면 안 된다');
    expect(body['memberName'], isNull);
  });

  test('GET /api/device-status 는 세션 없이는 403 이다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);

    final response = await http.get(
      h.uri('/api/device-status?deviceToken=device-1'),
    );
    expect(response.statusCode, 403);
    expect((jsonDecode(response.body) as Map)['error'], 'invalid_session');
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
}
