import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/services/checkin_event_bus.dart';

import '../helpers/checkin_server_harness.dart';

/// 판정을 읽고 그 action id 로 기록하는 한 번의 스캔.
Future<http.Response> _scan(
  CheckInServerHarness h, {
  String kind = 'checkIn',
}) async {
  final session = await h.issueSession();
  final body =
      jsonDecode((await h.nextAction(session)).body) as Map<String, Object?>;
  final actions = (body['actions'] as List).cast<Map>();
  final action = actions.firstWhere((a) => a['kind'] == kind);
  return http.post(
    h.uri('/api/checkin'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'session': session,
      'deviceToken': 'device-1',
      'actionId': action['id'],
    }),
  );
}

/// 연락처가 있는 회원을 만들고 `device-1` 을 그 회원에 묶어 둔다.
Future<int> _bindMember(CheckInServerHarness h) async {
  final id = await h.members.insert(
    const Member(name: '홍길동', parentContact: '010-1111-2222'),
  );
  await h.devices.bind('device-1', id);
  return id;
}

void main() {
  test('등원이 새로 기록되면 카운터에 이벤트를 흘려보낸다', () async {
    final h = await CheckInServerHarness.start();
    addTearDown(h.close);
    await _bindMember(h);
    final events = <CheckInEvent>[];
    final sub = h.server.checkInEventBus.events.listen(events.add);
    addTearDown(sub.cancel);

    expect((await _scan(h)).statusCode, 200);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single.memberName, '홍길동');
    expect(events.single.kind, CheckEventKind.checkedIn);
  });

  // 등원 직후의 재스캔은 거짓 하원이 되지 않고 차단된다. 완료 배너가 아니라 주의 배너가
  // 떠야 한다 — 그러지 않으면 방금 찍지 않은 사람의 완료 문구가 카운터에 뜬다.
  test('등원 직후의 재스캔은 완료가 아니라 차단으로 흘러간다', () async {
    final now = DateTime(2026, 10, 27, 15, 2);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    final memberId = await _bindMember(h);
    await h.attendance.insert(
      Attendance(
        memberId: memberId,
        date: '2026-10-27',
        checkInTime: DateTime(2026, 10, 27, 15, 0).toIso8601String(),
        status: AttendanceStatus.present,
      ),
    );
    final events = <CheckInEvent>[];
    final sub = h.server.checkInEventBus.events.listen(events.add);
    addTearDown(sub.cancel);

    final body = jsonDecode((await h.nextAction(await h.issueSession())).body);
    await Future<void>.delayed(Duration.zero);

    expect(body['action'], 'tooEarly');
    expect(events.map((e) => e.kind), [CheckEventKind.blockedTooEarly]);
    expect(events.single.remaining, const Duration(minutes: 28));
  });

  test('하원이 기록되면 하원 이벤트를 흘려보낸다', () async {
    final now = DateTime(2026, 10, 27, 18, 0);
    final h = await CheckInServerHarness.start(clock: () => now);
    addTearDown(h.close);
    final memberId = await _bindMember(h);
    await h.attendance.insert(
      Attendance(
        memberId: memberId,
        date: '2026-10-27',
        checkInTime: DateTime(2026, 10, 27, 15, 0).toIso8601String(),
        status: AttendanceStatus.present,
      ),
    );
    final events = <CheckInEvent>[];
    final sub = h.server.checkInEventBus.events.listen(events.add);
    addTearDown(sub.cancel);

    expect((await _scan(h, kind: 'checkOut')).statusCode, 200);
    await Future<void>.delayed(Duration.zero);

    expect(events.map((e) => e.kind), [CheckEventKind.checkedOut]);
  });
}
