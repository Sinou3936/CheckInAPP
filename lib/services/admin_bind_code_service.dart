import 'dart:math';

class _IssuedCode {
  final String code;
  final DateTime issuedAt;

  const _IssuedCode(this.code, this.issuedAt);
}

/// 관리자가 회원별로 발급하는 일회용 바인딩 코드.
///
/// 연락처가 없는 회원은 뒷 4자리로 본인을 확인할 수 없어 혼자 바인딩할 수 없다. 기기 토큰은
/// 폰 브라우저 안에만 있어 관리자 앱이 직접 묶을 수 없으므로, 관리자가 카운터에서 본인임을
/// 확인한 뒤 코드를 발급해 주고 학생이 자기 폰에서 입력하는 방식으로 대행한다.
///
/// 코드는 메모리에만 두고 한 번 쓰면 사라지며 회원당 하나만 유효하다 (새로 발급하면 이전 것이
/// 무효가 된다). 앱을 껐다 켜면 모두 사라지는 것이 의도다.
class AdminBindCodeService {
  final Duration ttl;

  final Random _random = Random.secure();
  final Map<int, _IssuedCode> _codes = {};

  AdminBindCodeService({this.ttl = const Duration(minutes: 5)});

  /// 회원에게 6자리 숫자 코드를 발급한다.
  String issue(int memberId, {DateTime? now}) {
    final issuedAt = now ?? DateTime.now();
    // 발급할 때 만료된 것을 치워 맵이 쌓이지 않게 한다.
    _codes.removeWhere((_, c) => !issuedAt.isBefore(c.issuedAt.add(ttl)));

    final code = _random.nextInt(1000000).toString().padLeft(6, '0');
    _codes[memberId] = _IssuedCode(code, issuedAt);
    return code;
  }

  /// 코드가 맞으면 소비하고 true. 틀리거나 만료됐으면 false — 틀린 시도는 코드를 소비하지 않는다.
  bool consume(int memberId, String code, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final issued = _codes[memberId];
    if (issued == null) return false;
    if (!current.isBefore(issued.issuedAt.add(ttl))) {
      _codes.remove(memberId);
      return false;
    }
    if (issued.code != code) return false;
    _codes.remove(memberId);
    return true;
  }
}
