import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/attendance_service.dart';

import '../helpers/test_db.dart';

/// 2026-10-16 은 금요일 (DateTime.weekday == 5).
const fridayWeekday = 5;
const mondayWeekday = 1;

class _Harness {
  final Database db;
  final MemberRepository members;
  final ClassRepository classes;
  final AttendanceRepository attendance;
  final AttendanceService service;

  _Harness(this.db)
    : members = MemberRepository(db),
      classes = ClassRepository(db),
      attendance = AttendanceRepository(db),
      service = AttendanceService(
        memberRepository: MemberRepository(db),
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      );

  static Future<_Harness> open() async => _Harness(await openTestDatabase());

  Future<void> close() => db.close();
}

void main() {
  test('determineStatus 는 유예 경계까지 출석, 그 뒤는 지각', () async {
    final h = await _Harness.open();
    final classStart = DateTime(2026, 10, 16, 15, 0);

    expect(
      h.service.determineStatus(classStart, DateTime(2026, 10, 16, 15, 5)),
      AttendanceStatus.present,
    );
    expect(
      h.service.determineStatus(
        classStart,
        classStart.add(const Duration(minutes: 10)),
      ),
      AttendanceStatus.present,
    );
    expect(
      h.service.determineStatus(
        classStart,
        classStart.add(const Duration(minutes: 10, seconds: 1)),
      ),
      AttendanceStatus.late,
    );
    await h.close();
  });

  test('recordCheckIn 은 반 시작 시각 기준으로 출석/지각을 정하고 recorded 를 돌려준다', () async {
    final h = await _Harness.open();
    final classId = await h.classes.insert(
      ClassModel(
        name: '금요반',
        startTime: '15:00',
        operatingDays: {fridayWeekday},
      ),
    );
    final memberId = await h.members.insert(
      Member(name: '홍길동', classId: classId),
    );

    final outcome = await h.service.recordCheckIn(
      memberId,
      now: DateTime(2026, 10, 16, 15, 3),
    );
    expect(outcome.status, CheckInStatus.recorded);
    expect(outcome.attendance.status, AttendanceStatus.present);
    expect(outcome.attendance.date, '2026-10-16');
    await h.close();
  });

  test('같은 날 두 번째 등원 스캔은 alreadyCheckedIn 이고 기록을 바꾸지 않는다', () async {
    final h = await _Harness.open();
    final classId = await h.classes.insert(
      ClassModel(
        name: '금요반',
        startTime: '15:00',
        operatingDays: {fridayWeekday},
      ),
    );
    final memberId = await h.members.insert(
      Member(name: '홍길동', classId: classId),
    );

    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 16, 15, 3));
    final second = await h.service.recordCheckIn(
      memberId,
      now: DateTime(2026, 10, 16, 20, 0),
    );

    expect(second.status, CheckInStatus.alreadyCheckedIn);
    expect(second.attendance.status, AttendanceStatus.present);
    expect(
      second.attendance.checkInTime,
      DateTime(2026, 10, 16, 15, 3).toIso8601String(),
    );
    await h.close();
  });

  test('반이 없는 회원의 등원은 출석으로 기록된다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '무소속', classId: null),
    );

    final outcome = await h.service.recordCheckIn(
      memberId,
      now: DateTime(2026, 10, 16, 23, 0),
    );
    expect(outcome.attendance.status, AttendanceStatus.present);
    await h.close();
  });

  test('recordCheckOut 은 열린 세션의 하원 시각을 채운다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );

    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 16, 15, 0));
    final outcome = await h.service.recordCheckOut(
      memberId,
      now: DateTime(2026, 10, 16, 18, 30),
    );

    expect(outcome.status, CheckOutStatus.recorded);
    expect(
      outcome.attendance!.checkOutTime,
      DateTime(2026, 10, 16, 18, 30).toIso8601String(),
    );
    await h.close();
  });

  test('자정을 넘겨 하원해도 등원한 날짜의 행에 기록된다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );

    await h.service.recordCheckIn(
      memberId,
      now: DateTime(2026, 10, 16, 23, 50),
    );
    final outcome = await h.service.recordCheckOut(
      memberId,
      now: DateTime(2026, 10, 17, 0, 20),
    );

    expect(outcome.status, CheckOutStatus.recorded);
    expect(outcome.attendance!.date, '2026-10-16');
    expect(
      outcome.attendance!.checkOutTime,
      DateTime(2026, 10, 17, 0, 20).toIso8601String(),
    );
    await h.close();
  });

  test('열린 세션이 둘이면 가장 최근 등원을 닫고 과거 세션은 그대로 둔다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );

    await h.service.recordCheckIn(
      memberId,
      now: DateTime(2026, 10, 16, 23, 50),
    );
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 17, 8, 0));
    final outcome = await h.service.recordCheckOut(
      memberId,
      now: DateTime(2026, 10, 17, 10, 0),
    );

    expect(outcome.attendance!.date, '2026-10-17');
    final yesterday = await h.attendance.getByMemberAndDate(
      memberId,
      '2026-10-16',
    );
    expect(yesterday!.checkOutTime, isNull);
    await h.close();
  });

  test('등원으로부터 12시간이 지나면 하원으로 닫히지 않는다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );

    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 16, 9, 0));
    final outcome = await h.service.recordCheckOut(
      memberId,
      now: DateTime(2026, 10, 16, 22, 0),
    );

    expect(outcome.status, CheckOutStatus.noOpenSession);
    await h.close();
  });

  test('등원 기록이 없으면 하원은 noOpenSession 이다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );

    final outcome = await h.service.recordCheckOut(
      memberId,
      now: DateTime(2026, 10, 16, 18, 0),
    );

    expect(outcome.status, CheckOutStatus.noOpenSession);
    expect(outcome.attendance, isNull);
    await h.close();
  });

  test('이미 하원한 뒤 다시 하원 스캔하면 alreadyCheckedOut 이다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );

    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 16, 15, 0));
    await h.service.recordCheckOut(
      memberId,
      now: DateTime(2026, 10, 16, 18, 0),
    );
    final again = await h.service.recordCheckOut(
      memberId,
      now: DateTime(2026, 10, 16, 18, 5),
    );

    expect(again.status, CheckOutStatus.alreadyCheckedOut);
    await h.close();
  });

  test('자정을 넘겨 하원한 뒤 다시 하원 스캔하면 alreadyCheckedOut 이다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );

    await h.service.recordCheckIn(
      memberId,
      now: DateTime(2026, 10, 16, 23, 50),
    );
    await h.service.recordCheckOut(
      memberId,
      now: DateTime(2026, 10, 17, 0, 20),
    );

    // 제대로 찍혔는지 못 믿고 2분 뒤 다시 찍는다. 세션은 어제 날짜 행에 있다.
    final again = await h.service.recordCheckOut(
      memberId,
      now: DateTime(2026, 10, 17, 0, 22),
    );

    expect(again.status, CheckOutStatus.alreadyCheckedOut);
    expect(again.attendance!.date, '2026-10-16');
    await h.close();
  });

  test('자동 결석 처리된 뒤 실제로 등원하면 등원으로 올라간다', () async {
    final h = await _Harness.open();
    final classId = await h.classes.insert(
      ClassModel(
        name: '금요반',
        startTime: '15:00',
        operatingDays: {fridayWeekday},
      ),
    );
    final memberId = await h.members.insert(
      Member(name: '늦게온사람', classId: classId),
    );

    await h.service.markAbsentees(DateTime(2026, 10, 16));
    final outcome = await h.service.recordCheckIn(
      memberId,
      now: DateTime(2026, 10, 16, 15, 3),
    );

    expect(outcome.status, CheckInStatus.recorded);
    expect(outcome.attendance.status, AttendanceStatus.present);
    expect(
      outcome.attendance.checkInTime,
      DateTime(2026, 10, 16, 15, 3).toIso8601String(),
    );
    await h.close();
  });

  test('같은 순간의 등원 스캔 두 건 중 하나만 recorded 다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );
    final at = DateTime(2026, 10, 16, 15, 0);

    final outcomes = await Future.wait([
      h.service.recordCheckIn(memberId, now: at),
      h.service.recordCheckIn(memberId, now: at),
    ]);

    expect(
      outcomes.where((o) => o.status == CheckInStatus.recorded).length,
      1,
      reason: '두 건 다 recorded 면 학부모에게 알림이 두 번 간다',
    );
    await h.close();
  });

  test('같은 순간의 하원 스캔 두 건 중 하나만 recorded 다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(
      const Member(name: '홍길동', classId: null),
    );
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 16, 15, 0));
    final at = DateTime(2026, 10, 16, 18, 0);

    final outcomes = await Future.wait([
      h.service.recordCheckOut(memberId, now: at),
      h.service.recordCheckOut(memberId, now: at),
    ]);

    expect(
      outcomes.where((o) => o.status == CheckOutStatus.recorded).length,
      1,
      reason: '두 건 다 recorded 면 학부모에게 하원 알림이 두 번 간다',
    );
    await h.close();
  });

  test('markAbsentees 는 운영 요일의 미체크 회원만 결석 처리한다', () async {
    final h = await _Harness.open();
    final fridayClassId = await h.classes.insert(
      ClassModel(
        name: '금요반',
        startTime: '15:00',
        operatingDays: {fridayWeekday},
      ),
    );
    final mondayClassId = await h.classes.insert(
      ClassModel(
        name: '월요반',
        startTime: '15:00',
        operatingDays: {mondayWeekday},
      ),
    );
    final absentId = await h.members.insert(
      Member(name: '결석자', classId: fridayClassId),
    );
    final presentId = await h.members.insert(
      Member(name: '출석자', classId: fridayClassId),
    );
    final mondayMemberId = await h.members.insert(
      Member(name: '월요일회원', classId: mondayClassId),
    );

    final friday = DateTime(2026, 10, 16);
    await h.service.recordCheckIn(
      presentId,
      now: DateTime(2026, 10, 16, 15, 1),
    );

    expect(await h.service.markAbsentees(friday), 1);

    final absentRecord = await h.attendance.getByMemberAndDate(
      absentId,
      AttendanceService.formatDate(friday),
    );
    expect(absentRecord!.status, AttendanceStatus.absent);
    expect(await h.attendance.getHistoryForMember(mondayMemberId), isEmpty);
    await h.close();
  });
}
