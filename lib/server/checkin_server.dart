import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/services/verification_session_service.dart';

/// 관리자 앱과 **같은 프로세스**에서 도는 체크인 서버.
///
/// 같은 SQLite 핸들을 저장소를 통해 직접 공유하므로 앱과 서버 사이에 별도 통신 계층이 없다.
/// 로컬 네트워크에만 바인딩되며 외부 호스팅을 쓰지 않는다.
///
/// 흐름: 학생이 QR 을 스캔하면 페이지가 열리면서 `GET /api/session` 으로 토큰을 검증하고
/// 확인 세션을 받는다. 이후 읽기 요청은 세션으로 한다 — QR 토큰은 30초마다 갱신되므로
/// 최초 1회 절차(이름 찾기 + 연락처 뒷 4자리)를 토큰으로 버티게 하면 반드시 실패한다.
class CheckInServer {
  final MemberRepository memberRepository;
  final DeviceBindingRepository deviceBindingRepository;

  /// `POST /api/checkin` 이 쓴다 (Task 11). 라우터 자리를 여기서 잡아둔다.
  final AttendanceService attendanceService;

  final QrTokenService qrTokenService;
  final VerificationSessionService verificationSessionService;

  HttpServer? _server;

  CheckInServer({
    required this.memberRepository,
    required this.deviceBindingRepository,
    required this.attendanceService,
    required this.qrTokenService,
    required this.verificationSessionService,
  });

  Router get _router {
    final router = Router();
    router.get('/api/session', _handleIssueSession);
    router.get('/api/members', _handleGetMembers);
    router.get('/api/device-status', _handleDeviceStatus);
    return router;
  }

  /// 실제로 바인딩된 포트를 돌려준다 (`port: 0` 이면 임의 포트).
  Future<int> start({int port = 8080}) async {
    _server = await shelf_io.serve(_router, InternetAddress.anyIPv4, port);
    return _server!.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Response _json(Object? body, {int statusCode = 200}) => Response(
    statusCode,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  /// 요청의 확인 세션을 검증한다. 유효하지 않으면 403 응답을, 유효하면 null 을 돌려준다.
  Response? _rejectUnlessSession(Request request) {
    final sessionId = request.url.queryParameters['session'];
    if (sessionId == null ||
        verificationSessionService.kindOf(sessionId) == null) {
      return _json({'error': 'invalid_session'}, statusCode: 403);
    }
    return null;
  }

  Future<Response> _handleIssueSession(Request request) async {
    final token = request.url.queryParameters['token'];
    final kind = token == null ? null : qrTokenService.kindOf(token);
    if (kind == null) {
      return _json({'error': 'invalid_token'}, statusCode: 403);
    }
    return _json({
      'sessionId': verificationSessionService.issue(kind),
      'kind': kind.name,
    });
  }

  /// 명단은 유효한 세션에만 내준다 — 그냥 열려 있으면 연락처 뒷 4자리를 전수 시도할
  /// 표적 목록을 내주는 셈이다.
  Future<Response> _handleGetMembers(Request request) async {
    final rejection = _rejectUnlessSession(request);
    if (rejection != null) return rejection;

    final members = await memberRepository.getAll();
    return _json(members.map((m) => {'id': m.id, 'name': m.name}).toList());
  }

  Future<Response> _handleDeviceStatus(Request request) async {
    final rejection = _rejectUnlessSession(request);
    if (rejection != null) return rejection;

    final deviceToken = request.url.queryParameters['deviceToken'];
    final binding = deviceToken == null
        ? null
        : await deviceBindingRepository.getByToken(deviceToken);
    if (binding == null) return _json({'bound': false});

    final member = await memberRepository.getById(binding.memberId);
    return _json({
      'bound': true,
      'memberId': binding.memberId,
      'memberName': member?.name,
    });
  }
}
