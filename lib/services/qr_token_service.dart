import 'dart:math';

/// 카운터 화면에 뜨는 **하나뿐인** 회전 QR 토큰.
///
/// 토큰은 종류를 담지 않는다. 등원인지 하원인지는 회원이 특정된 뒤 서버가 그 회원의 상태를
/// 보고 판정하므로, 토큰에 담을 의도가 애초에 없다. (예전에는 등원용·하원용 토큰이 따로
/// 있었고 스캔한 쪽이 의도였다 — 2026-10-27 개정이 그 결정을 대체했다.)
///
/// 토큰이 주기적으로 바뀌고 카운터에 직접 가야만 보이므로, 원격에서는 스캔할 QR 자체가
/// 없어 부정 체크가 원천 방지된다. 직전 토큰은 [graceDuration] 안에서만 통한다 — 막 갱신된
/// 순간에 스캔한 학생을 떨어뜨리지 않기 위함이다.
class QrTokenService {
  /// 토큰을 다시 돌려야 하는 간격. 이 클래스는 스스로 타이머를 돌리지 않는다 —
  /// 화면을 들고 있는 쪽이 이 값을 보고 [rotate] 를 호출한다. 현재 토큰의 수명 상한
  /// ([graceDuration] 과 합친 값)으로도 쓰인다.
  final Duration validityDuration;

  /// 갱신 직후 직전 토큰을 계속 받아주는 시간.
  final Duration graceDuration;

  String _current;
  String? _previous;
  DateTime? _rotatedAt;

  QrTokenService({
    this.validityDuration = const Duration(seconds: 30),
    this.graceDuration = const Duration(seconds: 10),
  }) : _current = _newToken();

  String get token => _current;

  /// 토큰을 교체하고 직전 값을 유예 대상으로 남긴다.
  void rotate({DateTime? now}) {
    _previous = _current;
    _current = _newToken();
    _rotatedAt = now ?? DateTime.now();
  }

  /// 토큰이 지금 통하는가.
  ///
  /// 현재 토큰도 마지막 [rotate] 로부터 [validityDuration] + [graceDuration] 이 지나면
  /// 거부한다. 회전 타이머가 죽어도(핫 리로드, 콜백 예외) 촬영한 QR 이 영구히 통하지 않게
  /// 하는 안전장치다. 한 번도 회전하지 않았으면(앱이 막 뜬 상태) 현재 토큰은 유효하다.
  bool isValid(String token, {DateTime? now}) {
    final checkTime = now ?? DateTime.now();
    final rotatedAt = _rotatedAt;

    if (token == _current) {
      if (rotatedAt == null) return true;
      return checkTime.isBefore(
        rotatedAt.add(validityDuration + graceDuration),
      );
    }

    if (rotatedAt == null || token != _previous) return false;
    return checkTime.isBefore(rotatedAt.add(graceDuration));
  }

  static String _newToken() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}
