class _Attempts {
  final int count;
  final DateTime lastFailureAt;

  const _Attempts(this.count, this.lastFailureAt);
}

/// 기기 바인딩의 본인 확인 실패를 세어 일정 횟수 뒤 그 기기를 잠근다.
///
/// 학부모 연락처 뒷 4자리는 1만 조합뿐이고, 체크인 서버는 학원 로컬 네트워크에 열려 있어
/// 스크립트로 전수 시도가 가능하다. 차단이 없으면 본인 확인은 장식이 된다.
///
/// 회원이 아니라 **기기 토큰**을 기준으로 센다 — 공격자는 표적 회원을 바꿔가며 시도할 수
/// 있지만, 폰에 저장된 기기 토큰은 자기 것을 쓸 수밖에 없다.
class BindAttemptThrottle {
  final int maxAttempts;
  final Duration lockout;

  final Map<String, _Attempts> _attempts = {};

  BindAttemptThrottle({
    this.maxAttempts = 5,
    this.lockout = const Duration(minutes: 10),
  });

  bool isLocked(String deviceToken, {DateTime? now}) {
    final attempts = _attempts[deviceToken];
    if (attempts == null) return false;
    if (attempts.count < maxAttempts) return false;

    final checkTime = now ?? DateTime.now();
    if (!checkTime.isBefore(attempts.lastFailureAt.add(lockout))) {
      _attempts.remove(deviceToken);
      return false;
    }
    return true;
  }

  void recordFailure(String deviceToken, {DateTime? now}) {
    final at = now ?? DateTime.now();
    // 앱이 하루 종일 떠 있으므로, 기록할 때 잠금이 풀린 항목을 치운다.
    _attempts.removeWhere(
      (_, a) =>
          a.count >= maxAttempts && !at.isBefore(a.lastFailureAt.add(lockout)),
    );

    final previous = _attempts[deviceToken];
    _attempts[deviceToken] = _Attempts((previous?.count ?? 0) + 1, at);
  }

  /// 본인 확인에 성공했을 때 부른다. 정상 사용자가 몇 번 틀린 뒤 맞췄다면 횟수가 남아
  /// 있어서는 안 된다.
  void clear(String deviceToken) => _attempts.remove(deviceToken);
}
