import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

import 'test_db.dart';

/// 인메모리 DB 위에 [CheckInServer] 를 임의 포트로 띄워 둔 테스트 하네스.
///
/// 서버 생성자 인자가 늘어도 이 한 곳만 고치면 된다. 테스트는 시작 직후
/// `addTearDown(h.close)` 로 정리를 걸어 둔다 — 단정이 실패해도 포트와 DB 핸들이 새지 않게.
class CheckInServerHarness {
  final Database db;
  final MemberRepository members;
  final DeviceBindingRepository devices;
  final NotificationLogRepository notificationLogs;
  final QrTokenService qr;
  final BindAttemptThrottle throttle;
  final CheckInServer server;
  final int port;

  CheckInServerHarness._({
    required this.db,
    required this.members,
    required this.devices,
    required this.notificationLogs,
    required this.qr,
    required this.throttle,
    required this.server,
    required this.port,
  });

  static Future<CheckInServerHarness> start() async {
    final db = await openTestDatabase();
    final members = MemberRepository(db);
    final devices = DeviceBindingRepository(db);
    final notificationLogs = NotificationLogRepository(db);
    final qr = QrTokenService();
    final throttle = BindAttemptThrottle();
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
        notifier: RecordingParentNotifier(notificationLogs),
      ),
      bindAttemptThrottle: throttle,
    );
    final port = await server.start(port: 0);
    return CheckInServerHarness._(
      db: db,
      members: members,
      devices: devices,
      notificationLogs: notificationLogs,
      qr: qr,
      throttle: throttle,
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
