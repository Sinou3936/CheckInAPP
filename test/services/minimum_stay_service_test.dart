import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/repositories/app_state_repository.dart';
import 'package:checkin_app/services/minimum_stay_service.dart';

import '../helpers/test_db.dart';

Future<(AppStateRepository, MinimumStayService)> fixture() async {
  final db = await openTestDatabase();
  addTearDown(db.close);
  final appState = AppStateRepository(db);
  return (appState, MinimumStayService(appState));
}

void main() {
  test('저장한 적이 없으면 기본값 30분', () async {
    final (_, service) = await fixture();
    expect(await service.read(), const Duration(minutes: 30));
  });

  test('저장한 값을 분으로 읽는다', () async {
    final (appState, service) = await fixture();
    await service.write(const Duration(minutes: 45));

    expect(await appState.get(MinimumStayService.stateKey), '45');
    expect(await service.read(), const Duration(minutes: 45));
  });

  // 설정 파일을 손으로 고친 시설이 하원 불가 상태에 빠지면 복구할 길이 없다. 읽기는
  // 예외를 던지지 않고 기본값으로 떨어진다.
  test('깨진 값은 기본값으로 떨어진다', () async {
    for (final broken in ['abc', '', '0', '-5', '720', '1000', '30.5']) {
      final (appState, service) = await fixture();
      await appState.set(MinimumStayService.stateKey, broken);

      expect(
        await service.read(),
        const Duration(minutes: 30),
        reason: '깨진 값 "$broken" 이 기본값으로 떨어지지 않았다',
      );
    }
  });

  test('하한 미만과 12시간 이상은 쓰기를 거부한다', () async {
    final (appState, service) = await fixture();
    await service.write(const Duration(minutes: 45));

    for (final rejected in [
      Duration.zero,
      const Duration(seconds: 30),
      const Duration(hours: 12),
      const Duration(hours: 13),
      const Duration(minutes: -5),
    ]) {
      await expectLater(
        () => service.write(rejected),
        throwsArgumentError,
        reason: '$rejected 를 거부하지 않았다',
      );
      expect(await appState.get(MinimumStayService.stateKey), '45');
    }
  });

  test('11시간 59분은 허용한다', () async {
    final (_, service) = await fixture();
    await service.write(const Duration(hours: 11, minutes: 59));

    expect(await service.read(), const Duration(hours: 11, minutes: 59));
  });

  test('isAllowed 는 화면과 서비스가 같이 쓰는 판정이다', () {
    expect(MinimumStayService.isAllowed(const Duration(minutes: 1)), isTrue);
    expect(MinimumStayService.isAllowed(Duration.zero), isFalse);
    expect(
      MinimumStayService.isAllowed(const Duration(hours: 11, minutes: 59)),
      isTrue,
    );
    expect(MinimumStayService.isAllowed(const Duration(hours: 12)), isFalse);
  });
}
