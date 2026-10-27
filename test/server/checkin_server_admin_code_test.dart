import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/models/member.dart';

import '../helpers/checkin_server_harness.dart';

Future<http.Response> _bind(
  CheckInServerHarness h, {
  required String session,
  required int memberId,
  required String adminCode,
  String deviceToken = 'device-1',
}) => http.post(
  h.uri('/api/bind'),
  headers: {'content-type': 'application/json'},
  body: jsonEncode({
    'session': session,
    'deviceToken': deviceToken,
    'memberId': memberId,
    'adminCode': adminCode,
  }),
);

Map _body(http.Response r) => jsonDecode(r.body) as Map;

void main() {
  test('연락처가 없는 회원도 관리자 발급 코드로 기기를 묶는다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    final code = h.server.adminBindCodeService.issue(memberId);
    final session = await h.issueSession();

    final response = await _bind(
      h,
      session: session,
      memberId: memberId,
      adminCode: code,
    );
    expect(response.statusCode, 200);
    expect(_body(response)['bound'], isTrue);
    expect((await h.devices.getByToken('device-1'))!.memberId, memberId);
  });

  test('코드는 한 번만 통한다 — 재사용하면 403 이고 묶이지 않는다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    final code = h.server.adminBindCodeService.issue(memberId);
    final session = await h.issueSession();

    await _bind(h, session: session, memberId: memberId, adminCode: code);
    final reuse = await _bind(
      h,
      session: session,
      memberId: memberId,
      adminCode: code,
      deviceToken: 'device-2',
    );
    expect(reuse.statusCode, 403);
    expect(_body(reuse)['error'], 'verification_failed');
    expect(await h.devices.getByToken('device-2'), isNull);
  });

  test('틀린 코드를 5회 보내면 올바른 코드도 429 로 잠긴다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    final code = h.server.adminBindCodeService.issue(memberId);
    final wrong = code == '000000' ? '000001' : '000000';
    final session = await h.issueSession();

    for (var i = 0; i < 5; i++) {
      final r = await _bind(
        h,
        session: session,
        memberId: memberId,
        adminCode: wrong,
      );
      expect(r.statusCode, 403);
    }
    final locked = await _bind(
      h,
      session: session,
      memberId: memberId,
      adminCode: code,
    );
    expect(locked.statusCode, 429);
    expect(await h.devices.getByToken('device-1'), isNull);
  });
}
