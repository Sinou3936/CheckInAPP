import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';

import '../helpers/test_db.dart';

void main() {
  test('insert 후 getByMemberAndDate 로 찾을 수 있다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T15:05:00.000',
        status: AttendanceStatus.present,
      ),
    );

    final found = await repo.getByMemberAndDate(1, '2026-10-16');
    expect(found!.status, AttendanceStatus.present);
    expect(await repo.getByMemberAndDate(1, '2026-10-17'), isNull);
    await db.close();
  });

  test('같은 회원·날짜로 두 번 insert 하면 첫 기록이 유지된다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T15:05:00.000',
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T18:00:00.000',
        status: AttendanceStatus.late,
      ),
    );

    final found = await repo.getByMemberAndDate(1, '2026-10-16');
    expect(found!.status, AttendanceStatus.present);
    await db.close();
  });

  test('getByDate 는 그 날짜의 모든 회원 기록을 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 2,
        date: '2026-10-16',
        status: AttendanceStatus.absent,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-17',
        status: AttendanceStatus.present,
      ),
    );

    final records = await repo.getByDate('2026-10-16');
    expect(records.map((a) => a.memberId).toSet(), {1, 2});
    await db.close();
  });

  test('getHistoryForMember 는 최신 날짜를 먼저 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-01',
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        status: AttendanceStatus.late,
      ),
    );

    final history = await repo.getHistoryForMember(1);
    expect(history.first.date, '2026-10-16');
    expect(history.last.date, '2026-10-01');
    await db.close();
  });

  test('findOpenSession 은 12시간 이내의 열린 세션을 찾는다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T15:00:00.000',
        checkOutTime: null,
        status: AttendanceStatus.present,
      ),
    );

    final open = await repo.findOpenSession(
      1,
      now: DateTime(2026, 10, 16, 18, 0),
    );
    expect(open!.date, '2026-10-16');
    await db.close();
  });

  test('findOpenSession 은 12시간이 지난 세션을 찾지 않는다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T09:00:00.000',
        checkOutTime: null,
        status: AttendanceStatus.present,
      ),
    );

    // 등원으로부터 13시간 뒤
    final open = await repo.findOpenSession(
      1,
      now: DateTime(2026, 10, 16, 22, 0),
    );
    expect(open, isNull);
    await db.close();
  });

  test('findOpenSession 은 이미 하원한 기록을 찾지 않는다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T15:00:00.000',
        checkOutTime: '2026-10-16T18:00:00.000',
        status: AttendanceStatus.present,
      ),
    );

    final open = await repo.findOpenSession(
      1,
      now: DateTime(2026, 10, 16, 18, 30),
    );
    expect(open, isNull);
    await db.close();
  });

  test('findOpenSession 은 열린 세션이 둘이면 등원이 가장 최근인 것을 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T23:50:00.000',
        checkOutTime: null,
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-17',
        checkInTime: '2026-10-17T08:00:00.000',
        checkOutTime: null,
        status: AttendanceStatus.present,
      ),
    );

    final open = await repo.findOpenSession(
      1,
      now: DateTime(2026, 10, 17, 10, 0),
    );
    expect(open!.date, '2026-10-17');
    await db.close();
  });

  test('결석 행(등원 시각 null)은 열린 세션도 미하원도 아니다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: null,
        checkOutTime: null,
        status: AttendanceStatus.absent,
      ),
    );

    final now = DateTime(2026, 10, 18, 12, 0);
    expect(await repo.findOpenSession(1, now: now), isNull);
    expect(await repo.findUnclosedSessions(now: now), isEmpty);
    await db.close();
  });

  test('update 는 하원 시각을 채운다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T15:00:00.000',
        status: AttendanceStatus.present,
      ),
    );
    final stored = await repo.getByMemberAndDate(1, '2026-10-16');

    await repo.update(
      Attendance(
        id: stored!.id,
        memberId: stored.memberId,
        date: stored.date,
        checkInTime: stored.checkInTime,
        checkOutTime: '2026-10-16T18:30:00.000',
        status: stored.status,
      ),
    );

    final reread = await repo.getByMemberAndDate(1, '2026-10-16');
    expect(reread!.checkOutTime, '2026-10-16T18:30:00.000');
    expect(reread.checkInTime, '2026-10-16T15:00:00.000');
    await db.close();
  });

  test('insert 는 이미 있는 회원·날짜면 0 을 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    const row = Attendance(
      memberId: 1,
      date: '2026-10-16',
      checkInTime: '2026-10-16T15:00:00.000',
      status: AttendanceStatus.present,
    );
    expect(await repo.insert(row), isNot(0));
    expect(await repo.insert(row), 0);
    await db.close();
  });

  test('closeSession 은 열린 세션을 닫고 1 을 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    final id = await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T15:00:00.000',
        status: AttendanceStatus.present,
      ),
    );

    expect(await repo.closeSession(id, '2026-10-16T18:00:00.000'), 1);
    final stored = await repo.getByMemberAndDate(1, '2026-10-16');
    expect(stored!.checkOutTime, '2026-10-16T18:00:00.000');
    await db.close();
  });

  test('closeSession 은 이미 닫힌 세션에 0 을 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    final id = await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T15:00:00.000',
        checkOutTime: '2026-10-16T18:00:00.000',
        status: AttendanceStatus.present,
      ),
    );

    expect(await repo.closeSession(id, '2026-10-16T19:00:00.000'), 0);
    final stored = await repo.getByMemberAndDate(1, '2026-10-16');
    expect(stored!.checkOutTime, '2026-10-16T18:00:00.000');
    await db.close();
  });

  test('fillCheckIn 은 결석 행에 등원 시각을 채우고 1 을 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    final id = await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: null,
        status: AttendanceStatus.absent,
      ),
    );

    expect(
      await repo.fillCheckIn(
        id,
        '2026-10-16T15:00:00.000',
        AttendanceStatus.present,
      ),
      1,
    );
    final stored = await repo.getByMemberAndDate(1, '2026-10-16');
    expect(stored!.checkInTime, '2026-10-16T15:00:00.000');
    expect(stored.status, AttendanceStatus.present);
    await db.close();
  });

  test('fillCheckIn 은 이미 등원 시각이 있으면 0 을 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    final id = await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T15:00:00.000',
        status: AttendanceStatus.present,
      ),
    );

    expect(
      await repo.fillCheckIn(
        id,
        '2026-10-16T16:00:00.000',
        AttendanceStatus.late,
      ),
      0,
    );
    final stored = await repo.getByMemberAndDate(1, '2026-10-16');
    expect(stored!.checkInTime, '2026-10-16T15:00:00.000');
    await db.close();
  });

  test('findLatestSessionWithin 은 이미 닫힌 세션도 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T23:50:00.000',
        checkOutTime: '2026-10-17T00:20:00.000',
        status: AttendanceStatus.present,
      ),
    );

    final latest = await repo.findLatestSessionWithin(
      1,
      now: DateTime(2026, 10, 17, 0, 22),
    );
    expect(latest!.date, '2026-10-16');
    expect(latest.checkOutTime, '2026-10-17T00:20:00.000');
    await db.close();
  });

  test('findLatestSessionWithin 은 창 밖의 세션은 돌려주지 않는다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T09:00:00.000',
        checkOutTime: '2026-10-16T10:00:00.000',
        status: AttendanceStatus.present,
      ),
    );

    final latest = await repo.findLatestSessionWithin(
      1,
      now: DateTime(2026, 10, 16, 22, 0),
    );
    expect(latest, isNull);
    await db.close();
  });

  test('findUnclosedSessions 는 12시간이 지난 미하원 기록만 돌려준다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-15',
        checkInTime: '2026-10-15T09:00:00.000',
        checkOutTime: null,
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T21:00:00.000',
        checkOutTime: null,
        status: AttendanceStatus.present,
      ),
    );

    final unclosed = await repo.findUnclosedSessions(
      now: DateTime(2026, 10, 16, 22, 0),
    );
    expect(unclosed.map((a) => a.date).toList(), ['2026-10-15']);
    await db.close();
  });

  test('findOpenSessionsWithin 은 12시간 이내의 열린 세션만 돌려주고 날짜로 거르지 않는다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    // now = 2026-10-17 00:30. 어제 23:50 등원(40분 전)은 날짜가 달라도 체류 중이다.
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T23:50:00.000',
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 2,
        date: '2026-10-16',
        checkInTime: '2026-10-16T12:00:00.000', // 12시간 30분 전: 창 밖
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 3,
        date: '2026-10-16',
        checkInTime: '2026-10-16T23:00:00.000',
        checkOutTime: '2026-10-17T00:05:00.000', // 닫힌 세션
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 4,
        date: '2026-10-16',
        checkInTime: null, // 결석 행
        status: AttendanceStatus.absent,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 5,
        date: '2026-10-17',
        checkInTime: '2026-10-17T00:10:00.000',
        status: AttendanceStatus.present,
      ),
    );

    final open = await repo.findOpenSessionsWithin(
      now: DateTime(2026, 10, 17, 0, 30),
    );
    expect(open.map((a) => a.memberId).toList()..sort(), [1, 5]);
    await db.close();
  });

  test('12시간 경계: 정확히 12시간 전 등원은 체류 중, 1ms 더 이전은 미하원이다 (틈도 겹침도 없다)', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    final now = DateTime(2026, 10, 17, 12, 0);

    // 정확히 12시간 전(=경계) 과 경계 1ms 밖.
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-17',
        checkInTime: '2026-10-17T00:00:00.000',
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 2,
        date: '2026-10-16',
        checkInTime: '2026-10-16T23:59:59.999',
        status: AttendanceStatus.present,
      ),
    );

    final open = await repo.findOpenSessionsWithin(now: now);
    final unclosed = await repo.findUnclosedSessions(now: now);

    expect(open.map((a) => a.memberId).toList(), [1]);
    expect(unclosed.map((a) => a.memberId).toList(), [2]);
    final both = open
        .map((a) => a.id)
        .toSet()
        .intersection(unclosed.map((a) => a.id).toSet());
    expect(both, isEmpty);
    await db.close();
  });

  test('findSessionsWithin 은 창 안의 열린 세션과 닫힌 세션을 모두 돌려주고 결석 행은 뺀다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    // now = 2026-10-17 09:00, 창 시작 = 2026-10-16 21:00
    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-16',
        checkInTime: '2026-10-16T23:50:00.000',
        checkOutTime: '2026-10-17T00:20:00.000', // 자정을 넘겨 닫힌 세션: 창 안
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 2,
        date: '2026-10-16',
        checkInTime: '2026-10-16T23:00:00.000', // 열린 세션: 창 안
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 3,
        date: '2026-10-16',
        checkInTime: '2026-10-16T09:00:00.000',
        checkOutTime: '2026-10-16T10:00:00.000', // 창 밖의 닫힌 세션
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 4,
        date: '2026-10-17',
        checkInTime: null, // 결석 행
        status: AttendanceStatus.absent,
      ),
    );

    final sessions = await repo.findSessionsWithin(
      now: DateTime(2026, 10, 17, 9, 0),
    );
    expect(sessions.map((a) => a.memberId).toList()..sort(), [1, 2]);
    await db.close();
  });

  test('findSessionsWithin 의 창 경계: 정확히 12시간 전 등원은 들어오고 1ms 전은 빠진다', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    final now = DateTime(2026, 10, 17, 12, 0);

    await repo.insert(
      const Attendance(
        memberId: 1,
        date: '2026-10-17',
        checkInTime: '2026-10-17T00:00:00.000',
        checkOutTime: '2026-10-17T01:00:00.000',
        status: AttendanceStatus.present,
      ),
    );
    await repo.insert(
      const Attendance(
        memberId: 2,
        date: '2026-10-16',
        checkInTime: '2026-10-16T23:59:59.999',
        checkOutTime: '2026-10-17T01:00:00.000',
        status: AttendanceStatus.present,
      ),
    );

    final sessions = await repo.findSessionsWithin(now: now);
    expect(sessions.map((a) => a.memberId).toList(), [1]);
    await db.close();
  });
}
