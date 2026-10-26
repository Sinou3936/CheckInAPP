import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/app_state_repository.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/absence_scheduler.dart';
import 'package:checkin_app/services/attendance_service.dart';
import '../helpers/test_db.dart';

class _Fixture {
  final Database db;
  final AttendanceRepository attendanceRepo;
  final AppStateRepository appState;
  final AbsenceScheduler scheduler;
  final int memberId;

  _Fixture(this.db, this.attendanceRepo, this.appState, this.scheduler, this.memberId);

  static Future<_Fixture> create(Set<int> operatingDays) async {
    final db = await openTestDatabase();
    final classRepo = ClassRepository(db);
    final memberRepo = MemberRepository(db);
    final attendanceRepo = AttendanceRepository(db);
    final appState = AppStateRepository(db);
    final classId = await classRepo.insert(
      ClassModel(name: '테스트반', startTime: '15:00', operatingDays: operatingDays),
    );
    final memberId = await memberRepo.insert(Member(name: '결석자', classId: classId));
    final scheduler = AbsenceScheduler(
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: classRepo,
        attendanceRepository: attendanceRepo,
      ),
      appStateRepository: appState,
    );
    return _Fixture(db, attendanceRepo, appState, scheduler, memberId);
  }

  Future<Attendance?> on(DateTime day) =>
      attendanceRepo.getByMemberAndDate(memberId, AttendanceService.formatDate(day));
}

void main() {
  test('첫 실행은 어제까지 처리한 것으로 기록하고 아무것도 쓰지 않는다', () async {
    final f = await _Fixture.create({5});
    addTearDown(f.db.close);

    await f.scheduler.checkNow(now: DateTime(2026, 9, 19)); // 토요일
    expect(await f.on(DateTime(2026, 9, 18)), isNull);
    expect(await f.appState.get(AbsenceScheduler.lastProcessedKey), '2026-09-18');
  });

  test('날짜가 넘어가면 전날 결석자를 처리한다', () async {
    final f = await _Fixture.create({5}); // 금요일 운영
    addTearDown(f.db.close);

    await f.scheduler.checkNow(now: DateTime(2026, 9, 18)); // 금요일: 어제(목)까지 처리됨
    expect(await f.on(DateTime(2026, 9, 18)), isNull);

    await f.scheduler.checkNow(now: DateTime(2026, 9, 19)); // 토요일: 금요일을 쓸어낸다
    expect((await f.on(DateTime(2026, 9, 18)))?.status, AttendanceStatus.absent);
  });

  test('꺼져 있던 며칠을 시작 시점에 따라잡는다', () async {
    final f = await _Fixture.create({1, 2, 3, 4, 5, 6, 7});
    addTearDown(f.db.close);

    await f.scheduler.checkNow(now: DateTime(2026, 9, 18)); // 목요일(17)까지 처리됨
    await f.scheduler.checkNow(now: DateTime(2026, 9, 22)); // 며칠 뒤 앱을 켬

    for (final day in [18, 19, 20, 21]) {
      expect((await f.on(DateTime(2026, 9, day)))?.status, AttendanceStatus.absent,
          reason: '9/$day');
    }
    expect(await f.on(DateTime(2026, 9, 22)), isNull, reason: '오늘은 아직 끝나지 않았다');
    expect(await f.appState.get(AbsenceScheduler.lastProcessedKey), '2026-09-21');
  });

  test('같은 날 다시 확인해도 다시 처리하지 않는다', () async {
    final f = await _Fixture.create({5});
    addTearDown(f.db.close);

    await f.scheduler.checkNow(now: DateTime(2026, 9, 18));
    await f.scheduler.checkNow(now: DateTime(2026, 9, 19));
    final first = await f.on(DateTime(2026, 9, 18));

    await f.scheduler.checkNow(now: DateTime(2026, 9, 19, 23));
    final second = await f.on(DateTime(2026, 9, 18));
    expect(second?.id, first?.id);
  });
}
