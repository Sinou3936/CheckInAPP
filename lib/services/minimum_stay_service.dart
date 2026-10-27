import 'package:checkin_app/repositories/app_state_repository.dart';

/// 시설이 정하는 **최소 체류 시간**. 등원 직후의 재스캔이 하원으로 기록되는 것을 막는다.
///
/// QR 이 하나가 되면서 등원·하원 판정이 회원 상태에서 나오므로, "방금 등원했는데 다시
/// 찍었다"를 구별하는 장치가 필요해졌다. 그 값을 코드에 못 박지 않는 이유는 학원과 헬스장의
/// 적정 값이 다르기 때문이다 — 시설이 정한다.
///
/// 시설 하나당 값 하나다. 반마다 다르게 두지 않는다.
class MinimumStayService {
  /// `app_state` 의 키. 분 단위 정수를 문자열로 담는다. 테이블이 이미 있으므로 스키마
  /// 변경이 없다.
  static const String stateKey = 'minimum_stay_minutes';

  /// 설정을 한 번도 건드리지 않은 시설에 적용된다.
  static const Duration defaultValue = Duration(minutes: 30);

  static const Duration minimum = Duration(minutes: 1);

  /// 하원 창(12시간)보다 **작아야** 한다. 같거나 크면 아무도 하원할 수 없다.
  /// 이 값 자체는 허용하지 않는다.
  static const Duration limit = Duration(hours: 12);

  final AppStateRepository appStateRepository;

  MinimumStayService(this.appStateRepository);

  /// 화면과 서비스가 **같은 판정**을 쓰도록 여기에 둔다. 화면이 따로 숫자를 적으면 저장은
  /// 거부되는데 화면은 통과시키는 조합이 생긴다.
  static bool isAllowed(Duration value) => value >= minimum && value < limit;

  /// 저장된 값. 없거나 허용 범위를 벗어나면 [defaultValue].
  ///
  /// **예외를 던지지 않는다.** 설정 파일을 손으로 고쳐 값이 깨진 시설이 하원 불가 상태에
  /// 빠지면 앱 안에서 복구할 길이 없다.
  Future<Duration> read() async {
    final stored = await appStateRepository.get(stateKey);
    final minutes = stored == null ? null : int.tryParse(stored);
    if (minutes == null) return defaultValue;

    final value = Duration(minutes: minutes);
    return isAllowed(value) ? value : defaultValue;
  }

  /// 허용 범위를 벗어나면 [ArgumentError] 를 던지고 아무것도 저장하지 않는다.
  Future<void> write(Duration value) {
    if (!isAllowed(value)) {
      throw ArgumentError.value(
        value,
        'value',
        '최소 체류 시간은 ${minimum.inMinutes}분 이상 ${limit.inHours}시간 미만이어야 한다',
      );
    }
    return appStateRepository.set(stateKey, value.inMinutes.toString());
  }
}
