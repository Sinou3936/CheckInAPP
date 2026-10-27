import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/repositories/app_state_repository.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/bind_attempt_throttle.dart';
import 'package:checkin_app/services/checkin_event_bus.dart';
import 'package:checkin_app/services/minimum_stay_service.dart';
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
  final AttendanceRepository attendance;
  final NotificationLogRepository notificationLogs;
  final AppStateRepository appState;
  final MinimumStayService minimumStay;
  final QrTokenService qr;
  final BindAttemptThrottle throttle;
  final CheckInEventBus eventBus;
  final CheckInServer server;
  final int port;

  CheckInServerHarness._({
    required this.db,
    required this.members,
    required this.devices,
    required this.attendance,
    required this.notificationLogs,
    required this.appState,
    required this.minimumStay,
    required this.qr,
    required this.throttle,
    required this.eventBus,
    required this.server,
    required this.port,
  });

  /// [clock] 을 주면 서버가 그 시각으로 판정한다. 최소 체류 시간과 하원 창(12시간) 경계는
  /// 실제 시각으로는 재현할 수 없다 — 오후에만 통과하는 테스트가 되기 때문이다.
  static Future<CheckInServerHarness> start({
    DateTime Function()? clock,
  }) async {
    final db = await openTestDatabase();
    final members = MemberRepository(db);
    final devices = DeviceBindingRepository(db);
    final attendance = AttendanceRepository(db);
    final notificationLogs = NotificationLogRepository(db);
    final appState = AppStateRepository(db);
    final minimumStay = MinimumStayService(appState);
    final qr = QrTokenService();
    final throttle = BindAttemptThrottle();
    final eventBus = CheckInEventBus();
    final server = CheckInServer(
      memberRepository: members,
      deviceBindingRepository: devices,
      attendanceService: AttendanceService(
        memberRepository: members,
        classRepository: ClassRepository(db),
        attendanceRepository: attendance,
      ),
      qrTokenService: qr,
      verificationSessionService: VerificationSessionService(),
      notificationService: NotificationService(
        memberRepository: members,
        notifier: RecordingParentNotifier(notificationLogs),
      ),
      bindAttemptThrottle: throttle,
      minimumStayService: minimumStay,
      checkInEventBus: eventBus,
      clock: clock ?? DateTime.now,
    );
    final port = await server.start(port: 0);
    return CheckInServerHarness._(
      db: db,
      members: members,
      devices: devices,
      attendance: attendance,
      notificationLogs: notificationLogs,
      appState: appState,
      minimumStay: minimumStay,
      qr: qr,
      throttle: throttle,
      eventBus: eventBus,
      server: server,
      port: port,
    );
  }

  Uri uri(String path) => Uri.parse('http://localhost:$port$path');

  /// 현재 QR 토큰으로 확인 세션을 받는다. [token] 을 주면 그 토큰으로 받는다.
  Future<String> issueSession([String? token]) async {
    final response = await http.get(
      uri('/api/session?token=${token ?? qr.token}'),
    );
    return (jsonDecode(response.body) as Map)['sessionId'] as String;
  }

  Future<http.Response> nextAction(
    String session, {
    String deviceToken = 'device-1',
  }) => http.get(
    uri(
      '/api/next-action?session=${Uri.encodeQueryComponent(session)}'
      '&deviceToken=${Uri.encodeQueryComponent(deviceToken)}',
    ),
  );

  Future<void> close() async {
    await server.stop();
    await eventBus.dispose();
    await db.close();
  }
}
