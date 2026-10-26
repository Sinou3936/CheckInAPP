import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/services/checkin_event_bus.dart';
import 'package:checkin_app/services/qr_token_service.dart';

import '../helpers/checkin_server_harness.dart';

Future<http.Response> _check(
  CheckInServerHarness h,
  String session,
) => http.post(
  h.uri('/api/checkin'),
  headers: {'content-type': 'application/json'},
  body: jsonEncode({'session': session, 'deviceToken': 'device-1'}),
);

/// 연락처가 있는 회원을 만들고 `device-1` 을 그 회원에 묶어 둔다.
Future<void> _bindMember(CheckInServerHarness h) async {
  final id = await h.members.insert(
    const Member(name: '홍길동', parentContact: '010-1111-2222'),
  );
  await h.devices.bind('device-1', id);
}

void main() {
  test('등원이 새로 기록되면 카운터에 이벤트를 흘려보낸다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await _bindMember(h);
    final events = <CheckInEvent>[];
    final sub = h.server.checkInEventBus.events.listen(events.add);
    addTearDown(sub.cancel);

    final session = await h.issueSession(h.qr.checkInToken);
    expect((await _check(h, session)).statusCode, 200);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single.memberName, '홍길동');
    expect(events.single.kind, QrKind.checkIn);
  });

  test('재스캔은 이벤트를 흘려보내지 않는다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await _bindMember(h);
    final events = <CheckInEvent>[];
    final sub = h.server.checkInEventBus.events.listen(events.add);
    addTearDown(sub.cancel);

    final first = await h.issueSession(h.qr.checkInToken);
    await _check(h, first);
    final again = await h.issueSession(h.qr.checkInToken);
    final response = await _check(h, again);
    await Future<void>.delayed(Duration.zero);

    expect(jsonDecode(response.body)['result'], 'alreadyCheckedIn');
    expect(events, hasLength(1));
  });

  test('하원이 기록되면 하원 이벤트를 흘려보낸다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await _bindMember(h);
    final events = <CheckInEvent>[];
    final sub = h.server.checkInEventBus.events.listen(events.add);
    addTearDown(sub.cancel);

    await _check(h, await h.issueSession(h.qr.checkInToken));
    await _check(h, await h.issueSession(h.qr.checkOutToken));
    await Future<void>.delayed(Duration.zero);

    expect(events.map((e) => e.kind), [QrKind.checkIn, QrKind.checkOut]);
  });
}
