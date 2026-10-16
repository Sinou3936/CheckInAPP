import 'dart:math';

/// 카운터 화면에 뜨는 두 QR 의 종류.
enum QrKind { checkIn, checkOut }

/// 등원용·하원용 회전 QR 토큰.
///
/// 두 토큰은 **서로 독립된 값**이다. 하나의 토큰에 종류를 파라미터로 붙이는 방식은 학생이
/// 등원 QR 로 받은 값의 파라미터만 바꿔 하원을 위조할 수 있으므로 쓰지 않는다.
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

  final Random _random = Random.secure();
  final Map<QrKind, String> _current = {};
  final Map<QrKind, String> _previous = {};
  DateTime? _rotatedAt;

  QrTokenService({
    this.validityDuration = const Duration(seconds: 30),
    this.graceDuration = const Duration(seconds: 10),
  }) {
    for (final kind in QrKind.values) {
      _current[kind] = _generateToken();
    }
  }

  String get checkInToken => _current[QrKind.checkIn]!;

  String get checkOutToken => _current[QrKind.checkOut]!;

  /// 두 토큰을 동시에 교체하고 직전 값을 유예 대상으로 남긴다.
  void rotate({DateTime? now}) {
    for (final kind in QrKind.values) {
      _previous[kind] = _current[kind]!;
      _current[kind] = _generateToken();
    }
    _rotatedAt = now ?? DateTime.now();
  }

  /// 토큰이 유효하면 그 종류를, 아니면 null 을 돌려준다.
  ///
  /// 현재 토큰도 마지막 [rotate] 로부터 [validityDuration] + [graceDuration] 이 지나면
  /// 거부한다. 회전 타이머가 죽어도(핫 리로드, 콜백 예외) 촬영한 QR 이 영구히 통하지 않게
  /// 하는 안전장치다. 한 번도 회전하지 않았으면(앱이 막 뜬 상태) 현재 토큰은 유효하다.
  QrKind? kindOf(String token, {DateTime? now}) {
    final checkTime = now ?? DateTime.now();
    final rotatedAt = _rotatedAt;

    for (final kind in QrKind.values) {
      if (_current[kind] != token) continue;
      final expired =
          rotatedAt != null &&
          !checkTime.isBefore(rotatedAt.add(validityDuration + graceDuration));
      return expired ? null : kind;
    }

    if (rotatedAt == null) return null;
    if (!checkTime.isBefore(rotatedAt.add(graceDuration))) return null;

    for (final kind in QrKind.values) {
      if (_previous[kind] == token) return kind;
    }
    return null;
  }

  String _generateToken() =>
      List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
}
