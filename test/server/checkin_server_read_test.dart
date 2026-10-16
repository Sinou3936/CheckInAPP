import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/bind_attempt_throttle.dart';
import 'package:checkin_app/services/notification_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/services/verification_session_service.dart';

import '../helpers/test_db.dart';

class _Harness {
  final Database db;
  final MemberRepository members;
  final DeviceBindingRepository devices;
  final QrTokenService qr;
  final CheckInServer server;
  final int port;

  _Harness({
    required this.db,
    required this.members,
    required this.devices,
    required this.qr,
    required this.server,
    required this.port,
  });

  static Future<_Harness> start() async {
    final db = await openTestDatabase();
    final members = MemberRepository(db);
    final devices = DeviceBindingRepository(db);
    final qr = QrTokenService();
    final server = CheckInServer(
      memberRepository: members,
      deviceBindingRepository: devices,
      attendanceService: AttendanceService(
        memberRepository: members,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: qr,
      verificationSessionService: VerificationSessionService(),
      notificationService: NotificationService(
        memberRepository: members,
        notifier: RecordingParentNotifier(NotificationLogRepository(db)),
      ),
      bindAttemptThrottle: BindAttemptThrottle(),
    );
    final port = await server.start(port: 0);
    return _Harness(
      db: db,
      members: members,
      devices: devices,
      qr: qr,
      server: server,
      port: port,
    );
  }

  Uri uri(String path) => Uri.parse('http://localhost:$port$path');

  Future<String> issueSession(String token) async {
    final response = await http.get(uri('/api/session?token=$token'));
    return (jsonDecode(response.body) as Map)['sessionId'] as String;
  }

  Future<void> close() async {
    await server.stop();
    await db.close();
  }
}

void main() {
  test('GET /api/session 은 등원 토큰에 checkIn 세션을 발급한다', () async {
    final h = await _Harness.start();

    final response = await http.get(
      h.uri('/api/session?token=${h.qr.checkInToken}'),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map;
    expect(body['kind'], 'checkIn');
    expect(body['sessionId'], isNotEmpty);

    await h.close();
  });

  test('GET /api/session 은 하원 토큰에 checkOut 세션을 발급한다', () async {
    final h = await _Harness.start();

    final response = await http.get(
      h.uri('/api/session?token=${h.qr.checkOutToken}'),
    );
    expect(response.statusCode, 200);
    expect((jsonDecode(response.body) as Map)['kind'], 'checkOut');

    await h.close();
  });

  test('GET /api/session 은 모르는 토큰을 403 으로 거부한다', () async {
    final h = await _Harness.start();

    final response = await http.get(h.uri('/api/session?token=nope'));
    expect(response.statusCode, 403);
    expect((jsonDecode(response.body) as Map)['error'], 'invalid_token');

    await h.close();
  });

  test('GET /api/members 는 세션 없이는 403 이다', () async {
    final h = await _Harness.start();

    final response = await http.get(h.uri('/api/members'));
    expect(response.statusCode, 403);
    expect((jsonDecode(response.body) as Map)['error'], 'invalid_session');

    await h.close();
  });

  test('GET /api/members 는 유효한 세션으로 명단을 돌려준다', () async {
    final h = await _Harness.start();
    await h.members.insert(const Member(name: '홍길동', classId: null));
    final session = await h.issueSession(h.qr.checkInToken);

    final response = await http.get(h.uri('/api/members?session=$session'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as List;
    expect(body.single['name'], '홍길동');

    await h.close();
  });

  test('GET /api/device-status 는 미바인딩 기기와 바인딩된 기기를 구분한다', () async {
    final h = await _Harness.start();
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

    await h.close();
  });

  test('확인 세션은 QR 이 갱신된 뒤에도 유효하다', () async {
    final h = await _Harness.start();
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

    await h.close();
  });

  test('GET /api/device-status 는 회원이 삭제된 바인딩을 미바인딩으로 본다', () async {
    final h = await _Harness.start();
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

    await h.close();
  });

  test('GET /api/device-status 는 세션 없이는 403 이다', () async {
    final h = await _Harness.start();

    final response = await http.get(
      h.uri('/api/device-status?deviceToken=device-1'),
    );
    expect(response.statusCode, 403);
    expect((jsonDecode(response.body) as Map)['error'], 'invalid_session');

    await h.close();
  });
}
