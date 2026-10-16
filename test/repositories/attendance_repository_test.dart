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
}
