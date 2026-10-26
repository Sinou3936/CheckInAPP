import 'dart:async';

import 'package:checkin_app/repositories/app_state_repository.dart';
import 'package:checkin_app/services/attendance_service.dart';

/// 하루가 끝난 날의 결석을 확정한다. 카운터 PC 가 밤에 꺼져 있어도 누락되지 않는다.
///
/// "마지막으로 결석 처리를 완료한 날짜"를 DB 에 저장해 두고, 확인할 때마다 그 다음 날부터
/// 어제까지를 하루씩 처리한다. 앱을 켜는 시점의 첫 확인이 곧 따라잡기다 (스펙 11번).
/// 오늘은 아직 끝나지 않았으므로 처리하지 않는다.
class AbsenceScheduler {
  static const lastProcessedKey = 'last_absence_processed_date';

  final AttendanceService attendanceService;
  final AppStateRepository appStateRepository;
  final Duration checkInterval;

  Timer? _timer;
  bool _running = false;

  AbsenceScheduler({
    required this.attendanceService,
    required this.appStateRepository,
    this.checkInterval = const Duration(hours: 1),
  });

  void start({DateTime? now}) {
    checkNow(now: now);
    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) => checkNow());
  }

  /// 미처리 날짜를 어제까지 처리한다. 처리 중에 다음 틱이 겹치면 그 틱은 건너뛴다.
  Future<void> checkNow({DateTime? now}) async {
    if (_running) return;
    _running = true;
    try {
      final current = now ?? DateTime.now();
      // DST 에 흔들리지 않도록 시각이 아니라 날짜 성분으로 하루씩 계산한다.
      final yesterday = DateTime(current.year, current.month, current.day - 1);

      final stored = await appStateRepository.get(lastProcessedKey);
      if (stored == null) {
        // 첫 실행: 거슬러 올라갈 기록이 없으므로 어제까지 처리한 것으로 시작한다.
        await appStateRepository.set(
          lastProcessedKey,
          AttendanceService.formatDate(yesterday),
        );
        return;
      }

      final last = DateTime.parse(stored);
      var day = DateTime(last.year, last.month, last.day + 1);
      while (!day.isAfter(yesterday)) {
        await attendanceService.markAbsentees(day);
        // 하루 처리할 때마다 저장한다 — 중간에 앱이 꺼져도 처리한 날을 다시 쓸지 않는다.
        await appStateRepository.set(
          lastProcessedKey,
          AttendanceService.formatDate(day),
        );
        day = DateTime(day.year, day.month, day.day + 1);
      }
    } finally {
      _running = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
