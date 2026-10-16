import 'dart:math';

import 'package:checkin_app/services/qr_token_service.dart';

class _Session {
  final QrKind kind;
  final DateTime issuedAt;

  const _Session(this.kind, this.issuedAt);
}

/// QR 을 스캔한 한 번의 체크에 대해 발급되는 단기 세션.
///
/// QR 토큰은 30초마다 갱신되는데 최초 1회 절차(이름 찾기 + 학부모 연락처 뒷 4자리 입력)는
/// 그보다 오래 걸린다. 토큰만으로 제출을 검증하면 그 절차는 **반드시** 실패하므로, 페이지가
/// 열릴 때 토큰을 검증해 세션을 발급하고 이후 요청은 세션으로 처리한다.
///
/// 세션은 유효한 QR 을 스캔해야만 발급되므로 "카운터에 직접 와야 한다"는 보증은 유지된다.
class VerificationSessionService {
  final Duration ttl;

  final Random _random = Random.secure();
  final Map<String, _Session> _sessions = {};

  VerificationSessionService({this.ttl = const Duration(minutes: 5)});

  /// 스캔한 QR 의 종류를 담은 세션을 발급한다.
  String issue(QrKind kind, {DateTime? now}) {
    final issuedAt = now ?? DateTime.now();
    // 앱은 하루 종일 떠 있고 스캔마다 세션이 하나 생기므로, 발급할 때 만료된 것을 치운다.
    _sessions.removeWhere(
      (_, session) => !issuedAt.isBefore(session.issuedAt.add(ttl)),
    );

    final id = _generateId();
    _sessions[id] = _Session(kind, issuedAt);
    return id;
  }

  /// 세션이 유효하면 그 종류를, 아니면 null 을 돌려준다.
  QrKind? kindOf(String sessionId, {DateTime? now}) {
    final session = _sessions[sessionId];
    if (session == null) return null;

    final checkTime = now ?? DateTime.now();
    if (!checkTime.isBefore(session.issuedAt.add(ttl))) {
      _sessions.remove(sessionId);
      return null;
    }
    return session.kind;
  }

  /// 사용 완료 처리. 이후 [kindOf] 는 null 을 돌려준다.
  void consume(String sessionId) => _sessions.remove(sessionId);

  String _generateId() =>
      List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
}
