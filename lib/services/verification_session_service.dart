import 'dart:math';

import 'package:checkin_app/models/check_kind.dart';

class _Session {
  final DateTime issuedAt;

  /// 이 세션에 대해 서버가 **허용한** 행동들. 키는 불투명한 1회용 id 다.
  final Map<String, CheckKind> actions = {};

  _Session(this.issuedAt);
}

/// QR 을 스캔한 한 번의 체크에 대해 발급되는 단기 세션.
///
/// QR 토큰은 30초마다 갱신되는데 최초 1회 절차(이름 찾기 + 학부모 연락처 뒷 4자리 입력)는
/// 그보다 오래 걸린다. 토큰만으로 제출을 검증하면 그 절차는 **반드시** 실패하므로, 페이지가
/// 열릴 때 토큰을 검증해 세션을 발급하고 이후 요청은 세션으로 처리한다.
///
/// 세션은 유효한 QR 을 스캔해야만 발급되므로 "카운터에 직접 와야 한다"는 보증은 유지된다.
///
/// **세션은 종류를 담지 않는다.** QR 이 하나이므로 담을 종류가 없다. 대신 서버가 판정을
/// 내린 뒤 그 판정이 허용한 행동마다 [registerAction] 으로 1회용 id 를 발급하고, 페이지는
/// 그 id 만 되돌려준다. 학생이 "등원/하원" 문자열을 보낼 수 있으면 하원을 위조할 수 있지만,
/// 서버가 내주지 않은 id 는 만들어낼 수 없다.
class VerificationSessionService {
  final Duration ttl;

  final Random _random = Random.secure();
  final Map<String, _Session> _sessions = {};

  VerificationSessionService({this.ttl = const Duration(minutes: 5)});

  /// 유효한 QR 을 스캔한 한 번의 체크에 대한 세션을 발급한다.
  String issue({DateTime? now}) {
    final issuedAt = now ?? DateTime.now();
    // 앱은 하루 종일 떠 있고 스캔마다 세션이 하나 생기므로, 발급할 때 만료된 것을 치운다.
    _sessions.removeWhere(
      (_, session) => !issuedAt.isBefore(session.issuedAt.add(ttl)),
    );

    final id = _generateId();
    _sessions[id] = _Session(issuedAt);
    return id;
  }

  bool isValid(String sessionId, {DateTime? now}) =>
      _liveSession(sessionId, now) != null;

  /// 판정이 허용한 행동 하나에 1회용 id 를 발급한다. 세션이 유효하지 않으면 null.
  String? registerAction(String sessionId, CheckKind kind, {DateTime? now}) {
    final session = _liveSession(sessionId, now);
    if (session == null) return null;

    final actionId = _generateId();
    session.actions[actionId] = kind;
    return actionId;
  }

  /// **그 세션이** 발급한 id 면 그 행동을, 아니면 null.
  ///
  /// id 를 세션에서 떼어내 보면 남의 세션에서 받은 id 로 기록을 만들 수 있다.
  CheckKind? actionOf(String sessionId, String actionId, {DateTime? now}) =>
      _liveSession(sessionId, now)?.actions[actionId];

  /// 사용 완료 처리. 이후 [isValid] 는 false 이고 그 세션의 action id 도 함께 죽는다 —
  /// 같은 id 로 두 번 기록해 학부모 알림이 두 번 나가는 것을 이것이 막는다.
  void consume(String sessionId) => _sessions.remove(sessionId);

  _Session? _liveSession(String sessionId, DateTime? now) {
    final session = _sessions[sessionId];
    if (session == null) return null;

    final checkTime = now ?? DateTime.now();
    if (!checkTime.isBefore(session.issuedAt.add(ttl))) {
      _sessions.remove(sessionId);
      return null;
    }
    return session;
  }

  String _generateId() =>
      List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
}
