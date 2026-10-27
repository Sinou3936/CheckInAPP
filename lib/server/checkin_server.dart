import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/check_kind.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/server/checkin_page.dart';
import 'package:checkin_app/services/admin_bind_code_service.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/bind_attempt_throttle.dart';
import 'package:checkin_app/services/checkin_event_bus.dart';
import 'package:checkin_app/services/minimum_stay_service.dart';
import 'package:checkin_app/services/notification_service.dart';
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
///
/// 회원이 특정되면 `GET /api/next-action` 이 **판정**을 내준다. QR 이 하나이므로 등원인지
/// 하원인지는 회원 상태에서 나온다. 판정이 허용한 행동마다 불투명한 1회용 action id 를 그
/// 세션에 발급하고, `POST /api/checkin` 은 그 id 만 받는다 — 종류를 문자열로 받으면 학생이
/// 그 값만 바꿔 하원을 위조할 수 있다.
class CheckInServer {
  final MemberRepository memberRepository;
  final DeviceBindingRepository deviceBindingRepository;

  final AttendanceService attendanceService;
  final QrTokenService qrTokenService;
  final VerificationSessionService verificationSessionService;

  /// 알림은 `recorded` 결과에서만 낸다 — 재스캔마다 학부모에게 알림이 가면 안 된다.
  final NotificationService notificationService;
  final BindAttemptThrottle bindAttemptThrottle;

  /// 연락처가 없는 회원을 위한 관리자 발급 일회용 코드. 앱이 같은 인스턴스를 공유해야 발급한
  /// 코드를 서버가 알아본다.
  final AdminBindCodeService adminBindCodeService;

  /// 최소 체류 시간. **요청마다 읽는다** — 설정을 바꾼 시설이 앱을 다시 띄워야 한다고
  /// 생각하면 안 된다.
  final MinimumStayService minimumStayService;

  /// 기록된 체크와 막힌 시도를 카운터 화면으로 흘려보내는 통로. 화면이 같은 인스턴스를
  /// 들어야 배너가 뜬다.
  final CheckInEventBus checkInEventBus;

  /// 판정의 기준 시각. 테스트가 최소 체류 시간과 하원 창 경계를 고정하려고 주입한다.
  final DateTime Function() clock;

  HttpServer? _server;

  CheckInServer({
    required this.memberRepository,
    required this.deviceBindingRepository,
    required this.attendanceService,
    required this.qrTokenService,
    required this.verificationSessionService,
    required this.notificationService,
    required this.bindAttemptThrottle,
    required this.minimumStayService,
    AdminBindCodeService? adminBindCodeService,
    CheckInEventBus? checkInEventBus,
    this.clock = DateTime.now,
  }) : adminBindCodeService = adminBindCodeService ?? AdminBindCodeService(),
       checkInEventBus = checkInEventBus ?? CheckInEventBus();

  Router get _router {
    final router = Router();
    router.get('/checkin', _handleCheckInPage);
    router.get('/api/session', _handleIssueSession);
    router.get('/api/members', _handleGetMembers);
    router.get('/api/device-status', _handleDeviceStatus);
    router.get('/api/next-action', _handleNextAction);
    router.post('/api/bind', _handleBind);
    router.post('/api/checkin', _handleCheckIn);
    return router;
  }

  /// 실제로 바인딩된 포트를 돌려준다 (`port: 0` 이면 임의 포트).
  ///
  /// 이미 떠 있으면 새로 띄우지 않고 기존 포트를 돌려준다 — 그러지 않으면 먼저 뜬 리스너가
  /// 핸들을 잃어 [stop] 으로도 내릴 수 없게 된다.
  Future<int> start({int port = 8080}) async {
    final running = _server;
    if (running != null) return running.port;
    _server = await shelf_io.serve(_router.call, InternetAddress.anyIPv4, port);
    return _server!.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Response _json(Object? body, {int statusCode = 200}) => Response(
    statusCode,
    body: jsonEncode(body),
    // 모바일 브라우저가 체크 응답이나 명단을 캐시하면 낡은 상태를 보여준다.
    headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
  );

  Response get _invalidSession =>
      _json({'error': 'invalid_session'}, statusCode: 403);

  /// 질의 파라미터로 받든 본문으로 받든 세션 판정은 이 한 곳을 지난다.
  bool _sessionIsValid(String? sessionId) =>
      sessionId != null && verificationSessionService.isValid(sessionId);

  /// 요청의 확인 세션(질의 파라미터)을 검증한다. 유효하지 않으면 403 응답을, 유효하면
  /// null 을 돌려준다.
  Response? _rejectUnlessSession(Request request) =>
      _sessionIsValid(request.url.queryParameters['session'])
      ? null
      : _invalidSession;

  String? _sessionIdOf(Map<String, Object?> body) {
    final sessionId = body['session'];
    return sessionId is String ? sessionId : null;
  }

  /// 본문의 기기 토큰. 없거나 문자열이 아니거나 비어 있으면 null — 두 엔드포인트가 같은
  /// 입력에 같은 답(`bad_request`)을 하도록 한 곳에서 판정한다. `member_required` 는
  /// "이 기기를 묶으라"는 뜻이므로 필드를 못 보낸 클라이언트에게 쓰면 안 된다.
  String? _deviceTokenOf(Map<String, Object?> body) {
    final deviceToken = body['deviceToken'];
    return deviceToken is String && deviceToken.isNotEmpty ? deviceToken : null;
  }

  /// JSON 객체 본문을 읽는다. 본문이 JSON 객체가 아니면 null.
  Future<Map<String, Object?>?> _readJsonBody(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Response get _badRequest => _json({'error': 'bad_request'}, statusCode: 400);

  Future<Response> _handleCheckInPage(Request request) async => Response.ok(
    checkInPageHtml,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      // 페이지가 낡은 채 캐시되면 서버가 바뀐 뒤에도 옛 엔드포인트를 부른다.
      'cache-control': 'no-store',
    },
  );

  /// 세션만 발급한다. **종류를 내주지 않는다** — QR 이 하나이므로 담을 종류가 없고,
  /// 내주면 페이지가 그것을 믿고 보내게 된다.
  Future<Response> _handleIssueSession(Request request) async {
    final token = request.url.queryParameters['token'];
    if (token == null || !qrTokenService.isValid(token)) {
      return _json({'error': 'invalid_token'}, statusCode: 403);
    }
    return _json({'sessionId': verificationSessionService.issue()});
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

    // 회원이 삭제됐는데 바인딩만 남은 경우를 미바인딩으로 본다 — 그러지 않으면 폰이
    // "null 님"을 그리고, 그 기기는 본인 확인 흐름으로 되돌아갈 길이 없다.
    final member = await memberRepository.getById(binding.memberId);
    if (member == null) return _json({'bound': false});

    return _json({
      'bound': true,
      'memberId': binding.memberId,
      'memberName': member.name,
    });
  }

  /// 처음 온 폰을 회원에 묶는다. 학부모 연락처 뒷 4자리로 본인을 확인한다.
  ///
  /// 세션을 소비하지 않는다 — 바인딩 뒤 같은 세션으로 곧바로 체크까지 할 수 있어야 한다.
  Future<Response> _handleBind(Request request) async {
    final body = await _readJsonBody(request);
    if (body == null) return _badRequest;
    if (!_sessionIsValid(_sessionIdOf(body))) return _invalidSession;

    final deviceToken = _deviceTokenOf(body);
    if (deviceToken == null) return _badRequest;

    // 잠금 판정에 회원이 필요해서 DB 조회보다 먼저 memberId 만 읽는다. 정수가 아니면
    // 시도 자체가 성립하지 않으므로 잠금과 무관하게 모르는 회원으로 답한다.
    final memberId = body['memberId'];
    if (memberId is! int) {
      return _json({'error': 'unknown_member'}, statusCode: 400);
    }

    // 4자리 비교보다 먼저 본다 — 잠긴 쪽은 올바른 4자리를 보내도 통과하면 안 된다.
    if (bindAttemptThrottle.isLocked(
      deviceToken: deviceToken,
      memberId: memberId,
    )) {
      return _json({'error': 'too_many_attempts'}, statusCode: 429);
    }

    final member = await memberRepository.getById(memberId);
    if (member == null) {
      return _json({'error': 'unknown_member'}, statusCode: 400);
    }

    // 관리자 발급 코드가 오면 뒷 4자리 대신 그것으로 본인을 확인한다. 6자리 숫자라서 4자리와
    // 마찬가지로 전수 시도가 가능하므로 틀리면 같은 잠금에 센다.
    final adminCode = body['adminCode'];
    if (adminCode is String && adminCode.isNotEmpty) {
      if (!adminBindCodeService.consume(memberId, adminCode)) {
        bindAttemptThrottle.recordFailure(
          deviceToken: deviceToken,
          memberId: memberId,
        );
        return _json({'error': 'verification_failed'}, statusCode: 403);
      }
      bindAttemptThrottle.clear(deviceToken: deviceToken, memberId: memberId);
      await deviceBindingRepository.bind(deviceToken, member.id!);
      return _json({'bound': true, 'memberName': member.name});
    }

    // 자력 바인딩 가능 여부의 판정은 Member 가 한다 — 화면도 같은 판정을 쓴다.
    if (!member.canSelfBind) {
      return _json({'error': 'verification_unavailable'}, statusCode: 403);
    }

    final digits = member.parentContactDigits;
    if (body['contactLast4'] != digits.substring(digits.length - 4)) {
      bindAttemptThrottle.recordFailure(
        deviceToken: deviceToken,
        memberId: memberId,
      );
      return _json({'error': 'verification_failed'}, statusCode: 403);
    }

    bindAttemptThrottle.clear(deviceToken: deviceToken, memberId: memberId);
    await deviceBindingRepository.bind(deviceToken, member.id!);
    return _json({'bound': true, 'memberName': member.name});
  }

  /// 이 기기의 회원을 찾는다. 회원이 삭제됐는데 바인딩만 남은 기기도 미바인딩으로 본다
  /// (`_handleDeviceStatus` 와 같은 판정).
  Future<Member?> _memberOf(String deviceToken) async {
    final binding = await deviceBindingRepository.getByToken(deviceToken);
    return binding == null ? null : memberRepository.getById(binding.memberId);
  }

  /// 이 스캔을 어떻게 처리할지 알려준다. **아무것도 기록하지 않는다.**
  ///
  /// 판정이 허용한 행동마다 1회용 action id 를 발급한다. 선택 상태(날짜 경계)에서는 둘이
  /// 나오고 하원이 먼저다. 차단·창 지남·완료에서는 빈 배열이다.
  Future<Response> _handleNextAction(Request request) async {
    final sessionId = request.url.queryParameters['session'];
    if (!_sessionIsValid(sessionId)) return _invalidSession;

    final deviceToken = request.url.queryParameters['deviceToken'];
    final member = deviceToken == null ? null : await _memberOf(deviceToken);
    if (member == null) {
      return _json({'error': 'member_required'}, statusCode: 400);
    }

    final judgment = await attendanceService.judge(
      member.id!,
      minimumStay: await minimumStayService.read(),
      now: clock(),
    );

    // 차단은 아무것도 기록하지 않으므로 이 배너가 유일한 흔적이다. 학생이 카운터 앞에 서
    // 있는 지금이 직원이 알아야 하는 순간이다.
    final blocked = _blockedEventKind(judgment.action);
    if (blocked != null) {
      checkInEventBus.publish(
        CheckInEvent(
          memberName: member.name,
          kind: blocked,
          remaining: judgment.remaining,
        ),
      );
    }

    return _json(_judgmentBody(judgment, member, sessionId!));
  }

  static CheckEventKind? _blockedEventKind(CheckAction action) =>
      switch (action) {
        CheckAction.tooEarly => CheckEventKind.blockedTooEarly,
        CheckAction.overdue => CheckEventKind.blockedOverdue,
        _ => null,
      };

  /// 판정 응답 본문. 읽기 경로와 `state_changed` 응답이 **같은 모양**을 쓰도록 한 곳에
  /// 둔다 — 다르면 페이지가 재확인 화면을 그리지 못한다.
  Map<String, Object?> _judgmentBody(
    CheckJudgment judgment,
    Member member,
    String sessionId,
  ) {
    // 선택 상태에서는 하원을 먼저 보여준다. 나가는 사람이 더 흔한 상황이다.
    final kinds = [
      if (judgment.allowedKinds.contains(CheckKind.checkOut))
        CheckKind.checkOut,
      if (judgment.allowedKinds.contains(CheckKind.checkIn)) CheckKind.checkIn,
    ];
    final open = judgment.openSession;
    return {
      'action': judgment.action.name,
      'memberName': member.name,
      // 올림한다. 90초 남았는데 "1분 뒤" 라고 하면 그 학생은 한 번 더 헛걸음한다.
      if (judgment.remaining != null)
        'remainingMinutes': (judgment.remaining!.inSeconds / 60).ceil(),
      if (open != null)
        'openSession': {
          'date': open.date,
          'checkInTime': open.checkInTime!.substring(11, 16),
        },
      'actions': [
        for (final kind in kinds)
          {
            'id': verificationSessionService.registerAction(sessionId, kind),
            'kind': kind.name,
          },
      ],
    };
  }

  /// 묶인 폰의 등원 또는 하원을 기록한다.
  ///
  /// 종류는 **action id** 가 정한다. 본문의 다른 필드는 보지 않는다 — 종류를 문자열로
  /// 받으면 학생이 그 값만 바꿔 하원을 위조할 수 있다.
  ///
  /// 쓰기 직전에 **다시 판정한다.** 확인 화면이 뜬 뒤 관리자 보정 등으로 상태가 바뀔 수
  /// 있고, 그때는 아무것도 쓰지 않고 새 판정을 돌려준다.
  Future<Response> _handleCheckIn(Request request) async {
    final body = await _readJsonBody(request);
    if (body == null) return _badRequest;
    final sessionId = _sessionIdOf(body);
    if (!_sessionIsValid(sessionId)) return _invalidSession;

    final deviceToken = _deviceTokenOf(body);
    if (deviceToken == null) return _badRequest;

    final actionId = body['actionId'];
    if (actionId is! String || actionId.isEmpty) return _badRequest;

    final member = await _memberOf(deviceToken);
    if (member == null) {
      return _json({'error': 'member_required'}, statusCode: 400);
    }

    final kind = verificationSessionService.actionOf(sessionId!, actionId);
    if (kind == null) {
      return _json({'error': 'invalid_action'}, statusCode: 403);
    }

    final now = clock();
    final minimumStay = await minimumStayService.read();
    final judgment = await attendanceService.judge(
      member.id!,
      minimumStay: minimumStay,
      now: now,
    );
    if (!judgment.allowedKinds.contains(kind)) {
      return _json({
        'error': 'state_changed',
        ..._judgmentBody(judgment, member, sessionId),
      }, statusCode: 409);
    }

    final Map<String, Object?> result;
    switch (kind) {
      case CheckKind.checkIn:
        final outcome = await attendanceService.recordCheckIn(
          member.id!,
          now: now,
        );
        if (outcome.status == CheckInStatus.recorded) {
          await notificationService.onCheckIn(member.id!, now);
          // 새로 기록된 등원만 카운터에 알린다 — 재스캔(alreadyCheckedIn)은 알리지 않는다.
          checkInEventBus.publish(
            CheckInEvent(
              memberName: member.name,
              kind: CheckEventKind.checkedIn,
              isLate: outcome.attendance.status == AttendanceStatus.late,
            ),
          );
          result = {
            'result': 'checkedIn',
            'memberName': member.name,
            'status': outcome.attendance.status.name,
          };
        } else {
          result = {'result': 'alreadyCheckedIn', 'memberName': member.name};
        }
      case CheckKind.checkOut:
        final outcome = await attendanceService.recordCheckOut(
          member.id!,
          minimumStay: minimumStay,
          now: now,
        );
        switch (outcome.status) {
          case CheckOutStatus.noOpenSession:
            return _json({'error': 'no_open_session'}, statusCode: 400);
          case CheckOutStatus.recorded:
            await notificationService.onCheckOut(member.id!, now);
            checkInEventBus.publish(
              CheckInEvent(
                memberName: member.name,
                kind: CheckEventKind.checkedOut,
              ),
            );
            result = {'result': 'checkedOut', 'memberName': member.name};
          case CheckOutStatus.alreadyCheckedOut:
            result = {'result': 'alreadyCheckedOut', 'memberName': member.name};
          case CheckOutStatus.tooEarly:
            // 판정이 이미 막았어야 한다. 여기까지 오면 그 사이 상태가 또 바뀐 것이다.
            return _json({
              'error': 'state_changed',
              ..._judgmentBody(
                await attendanceService.judge(
                  member.id!,
                  minimumStay: minimumStay,
                  now: now,
                ),
                member,
                sessionId,
              ),
            }, statusCode: 409);
        }
    }

    verificationSessionService.consume(sessionId);
    return _json(result);
  }
}
