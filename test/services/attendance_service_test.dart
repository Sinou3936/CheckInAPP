import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/check_kind.dart';
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

  /// 최소 체류 시간을 기본값(30분)으로 둔 하원. 그 규칙 자체를 보는 테스트만 값을 넘긴다.
  Future<CheckOutOutcome> checkOut(
    int memberId, {
    required DateTime now,
    Duration minimumStay = const Duration(minutes: 30),
  }) => service.recordCheckOut(memberId, now: now, minimumStay: minimumStay);

  /// 판정도 같은 기본값을 쓴다.
  Future<CheckJudgment> judge(
    int memberId, {
    required DateTime now,
    Duration minimumStay = const Duration(minutes: 30),
  }) => service.judge(memberId, now: now, minimumStay: minimumStay);

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
    final outcome = await h.checkOut(
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
    final outcome = await h.checkOut(
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
    final outcome = await h.checkOut(
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
    final outcome = await h.checkOut(
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

    final outcome = await h.checkOut(
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
    await h.checkOut(memberId, now: DateTime(2026, 10, 16, 18, 0));
    final again = await h.checkOut(
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
    await h.checkOut(memberId, now: DateTime(2026, 10, 17, 0, 20));

    // 제대로 찍혔는지 못 믿고 2분 뒤 다시 찍는다. 세션은 어제 날짜 행에 있다.
    final again = await h.checkOut(
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
      h.checkOut(memberId, now: at),
      h.checkOut(memberId, now: at),
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

  // --- 판정 (설계 문서 판정표 1~8번) ---
  //
  // 오늘 행과 12시간 창은 같은 것이 아니다. 섞으면 어제 열린 세션이 남은 학생의 오늘 아침
  // 스캔이 하원으로 판정돼 거짓 하원 알림이 나가고 오늘 등원이 사라진다.

  test('판정 1번: 기록이 없으면 등원', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));

    final judgment = await h.judge(
      memberId,
      now: DateTime(2026, 10, 27, 15, 0),
    );

    expect(judgment.action, CheckAction.checkIn);
    expect(judgment.openSession, isNull);
    await h.close();
  });

  test('판정 2번: 자동 결석 행만 있으면 등원', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.attendance.insert(
      Attendance(
        memberId: memberId,
        date: '2026-10-27',
        checkInTime: null,
        status: AttendanceStatus.absent,
      ),
    );

    final judgment = await h.judge(
      memberId,
      now: DateTime(2026, 10, 27, 15, 0),
    );

    expect(judgment.action, CheckAction.checkIn);
    await h.close();
  });

  test('판정 3번: 오늘 열린 행이 최소 체류 시간을 넘겼으면 하원', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 27, 15, 0));

    final judgment = await h.judge(
      memberId,
      now: DateTime(2026, 10, 27, 18, 0),
    );

    expect(judgment.action, CheckAction.checkOut);
    expect(judgment.openSession!.date, '2026-10-27');
    await h.close();
  });

  test('판정 4번: 최소 체류 시간 미경과면 차단이고 남은 시간을 준다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 27, 15, 0));

    final judgment = await h.judge(
      memberId,
      now: DateTime(2026, 10, 27, 15, 12),
    );

    expect(judgment.action, CheckAction.tooEarly);
    expect(judgment.remaining, const Duration(minutes: 18));
    await h.close();
  });

  test('판정 경계: 최소 체류 시간 정각은 하원이다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 27, 15, 0));

    final justBefore = DateTime(
      2026,
      10,
      27,
      15,
      30,
    ).subtract(const Duration(milliseconds: 1));
    expect(
      (await h.judge(memberId, now: justBefore)).action,
      CheckAction.tooEarly,
    );
    expect(
      (await h.judge(memberId, now: DateTime(2026, 10, 27, 15, 30))).action,
      CheckAction.checkOut,
    );
    await h.close();
  });

  test('판정 5번: 오늘 열린 행이 12시간을 넘겼으면 창 지남', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 27, 2, 0));

    final judgment = await h.judge(
      memberId,
      now: DateTime(2026, 10, 27, 15, 0),
    );

    expect(judgment.action, CheckAction.overdue);
    expect(judgment.openSession!.date, '2026-10-27');
    await h.close();
  });

  test('판정 6번: 오늘 이미 하원했으면 완료', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 27, 15, 0));
    await h.checkOut(memberId, now: DateTime(2026, 10, 27, 18, 0));

    final judgment = await h.judge(
      memberId,
      now: DateTime(2026, 10, 27, 18, 5),
    );

    expect(judgment.action, CheckAction.alreadyCheckedOut);
    await h.close();
  });

  test('판정 7번: 어제 열린 세션이 창 안이고 미경과면 차단', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(
      memberId,
      now: DateTime(2026, 10, 26, 23, 50),
    );

    final judgment = await h.judge(memberId, now: DateTime(2026, 10, 27, 0, 5));

    expect(judgment.action, CheckAction.tooEarly);
    expect(judgment.remaining, const Duration(minutes: 15));
    expect(judgment.openSession!.date, '2026-10-26');
    await h.close();
  });

  // 어제 23:50 등원이 열린 채 오늘 08:00 에 스캔한 상태는 "자정 넘겨 퇴장" 과 "오늘 재등원"
  // 에서 똑같이 생긴다. 한쪽으로 기본값을 정하면 반대쪽이 반드시 깨지므로 학생에게 묻는다.
  test('판정 8번: 어제 열린 세션이 창 안이고 경과했으면 선택', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(
      memberId,
      now: DateTime(2026, 10, 26, 23, 50),
    );

    final judgment = await h.judge(memberId, now: DateTime(2026, 10, 27, 8, 0));

    expect(judgment.action, CheckAction.choice);
    expect(judgment.openSession!.date, '2026-10-26');
    expect(judgment.openSession!.checkInTime, contains('23:50'));
    await h.close();
  });

  test('어제 열린 세션이 12시간 창 밖이면 등원이다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 26, 19, 0));

    final judgment = await h.judge(memberId, now: DateTime(2026, 10, 27, 8, 0));

    expect(judgment.action, CheckAction.checkIn);
    await h.close();
  });

  test('allowedKinds: 선택은 등원과 하원을 모두 허용한다', () {
    expect(const CheckJudgment(CheckAction.checkIn).allowedKinds, {
      CheckKind.checkIn,
    });
    expect(const CheckJudgment(CheckAction.checkOut).allowedKinds, {
      CheckKind.checkOut,
    });
    expect(const CheckJudgment(CheckAction.choice).allowedKinds, {
      CheckKind.checkIn,
      CheckKind.checkOut,
    });
  });

  test('allowedKinds: 차단·창 지남·완료는 아무 행동도 허용하지 않는다', () {
    for (final action in [
      CheckAction.tooEarly,
      CheckAction.overdue,
      CheckAction.alreadyCheckedOut,
    ]) {
      expect(
        CheckJudgment(action).allowedKinds,
        isEmpty,
        reason: '$action 이 행동을 허용했다',
      );
    }
  });

  // 판정을 건너뛴 호출자가 생겨도 기록이 새지 않게 기록 메서드에서도 막는다.
  test('recordCheckOut 은 최소 체류 시간 안에는 하원을 기록하지 않는다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 27, 15, 0));

    final outcome = await h.checkOut(
      memberId,
      now: DateTime(2026, 10, 27, 15, 12),
    );

    expect(outcome.status, CheckOutStatus.tooEarly);
    final stored = await h.attendance.getByMemberAndDate(
      memberId,
      '2026-10-27',
    );
    expect(stored!.checkOutTime, isNull);
    await h.close();
  });

  test('최소 체류 시간을 짧게 두면 그만큼 일찍 하원된다', () async {
    final h = await _Harness.open();
    final memberId = await h.members.insert(const Member(name: '홍길동'));
    await h.service.recordCheckIn(memberId, now: DateTime(2026, 10, 27, 15, 0));

    final outcome = await h.checkOut(
      memberId,
      now: DateTime(2026, 10, 27, 15, 12),
      minimumStay: const Duration(minutes: 5),
    );

    expect(outcome.status, CheckOutStatus.recorded);
    await h.close();
  });
}
