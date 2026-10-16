class _Attempts {
  final int count;
  final DateTime lastFailureAt;

  const _Attempts(this.count, this.lastFailureAt);
}

/// 기기 바인딩의 본인 확인 실패를 세어 일정 횟수 뒤 잠근다.
///
/// 학부모 연락처 뒷 4자리는 1만 조합뿐이고, 체크인 서버는 학원 로컬 네트워크에 열려 있어
/// 스크립트로 전수 시도가 가능하다. 차단이 없으면 본인 확인은 장식이 된다.
///
/// 실패를 **두 키로** 센다. 어느 한쪽이라도 잠겨 있으면 잠긴 것이다.
/// - **기기 토큰**: 한 기기가 여러 회원을 돌아가며 찍어보는 것을 막는다.
/// - **회원**: 기기 토큰은 요청 본문으로 오는 값이라 스크립트가 시도마다 새로 만들어 보낼 수
///   있다. 기기 토큰만 세면 그 방법으로 한 회원의 1만 조합을 카운터에 걸리지 않고 돌릴 수
///   있으므로, 표적이 되는 회원 쪽에서도 센다.
///
/// 감수한 대가: 누군가 특정 회원의 뒷 4자리를 5번 틀려 보내면 그 회원은 [lockout] 동안
/// 스스로 바인딩할 수 없다. 바인딩은 폰당 한 번뿐이고 관리자가 카운터에서 대행할 수 있다 —
/// 영구적인 가짜 신원보다 가벼운 쪽을 택했으므로 이를 완화하는 장치는 두지 않는다.
class BindAttemptThrottle {
  final int maxAttempts;
  final Duration lockout;

  final Map<String, _Attempts> _attempts = {};

  BindAttemptThrottle({
    this.maxAttempts = 5,
    this.lockout = const Duration(minutes: 10),
  });

  static String _deviceKey(String deviceToken) => 'device:$deviceToken';
  static String _memberKey(int memberId) => 'member:$memberId';

  bool isLocked({
    required String deviceToken,
    required int memberId,
    DateTime? now,
  }) {
    final checkTime = now ?? DateTime.now();
    // 두 키를 모두 평가한다 (단락 평가로 건너뛰면 만료된 항목이 남는다).
    final deviceLocked = _isKeyLocked(_deviceKey(deviceToken), checkTime);
    final memberLocked = _isKeyLocked(_memberKey(memberId), checkTime);
    return deviceLocked || memberLocked;
  }

  void recordFailure({
    required String deviceToken,
    required int memberId,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    // 앱이 하루 종일 떠 있고 기기 토큰은 호출자가 마음대로 만들 수 있으므로, 기록할 때
    // 창이 지난 항목을 임계 도달 여부와 무관하게 치운다. 그래야 맵이 자라지 않고, "연속"이
    // 창 안에서 이어진 실패를 뜻한다 — 아침의 오타 네 번이 몇 주 뒤 잠금의 씨앗이 되지 않는다.
    _attempts.removeWhere((_, a) => _isExpired(a, at));

    for (final key in [_deviceKey(deviceToken), _memberKey(memberId)]) {
      _attempts[key] = _Attempts((_attempts[key]?.count ?? 0) + 1, at);
    }
  }

  /// 본인 확인에 성공했을 때 부른다. 정상 사용자가 몇 번 틀린 뒤 맞췄다면 횟수가 남아
  /// 있어서는 안 된다.
  void clear({required String deviceToken, required int memberId}) {
    _attempts.remove(_deviceKey(deviceToken));
    _attempts.remove(_memberKey(memberId));
  }

  bool _isKeyLocked(String key, DateTime now) {
    final attempts = _attempts[key];
    if (attempts == null) return false;
    if (_isExpired(attempts, now)) {
      _attempts.remove(key);
      return false;
    }
    return attempts.count >= maxAttempts;
  }

  bool _isExpired(_Attempts attempts, DateTime now) =>
      !now.isBefore(attempts.lastFailureAt.add(lockout));
}
