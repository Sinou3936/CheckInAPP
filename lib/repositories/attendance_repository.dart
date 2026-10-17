import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/attendance.dart';

/// 일별 출결 기록 저장소.
///
/// `attendance` 는 `UNIQUE(member_id, date)` 라 회원·날짜당 한 행이고, 그 한 행이 등원
/// 시각과 하원 시각을 같이 들고 있다. 한 번의 방문은 **등원한 날짜의 행**에 귀속되므로,
/// 자정을 넘겨 하원해도 새 행이 생기지 않는다.
///
/// `check_in_time` / `check_out_time` 은 ISO8601 문자열이다. ISO8601 은 사전순 정렬이
/// 시간순과 일치하므로, 시간 범위 조회는 경계 시각을 문자열로 만들어 SQL 비교에 그대로 쓴다.
class AttendanceRepository {
  final Database db;
  AttendanceRepository(this.db);

  /// 첫 쓰기가 이긴다 — `UNIQUE(member_id, date)` 충돌은 무시된다.
  Future<int> insert(Attendance attendance) => db.insert(
    'attendance',
    attendance.toMap(),
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );

  /// 행 전체를 덮어쓴다. 관리자 보정이 이 경로를 쓴다.
  Future<void> update(Attendance attendance) => db.update(
    'attendance',
    attendance.toMap(),
    where: 'id = ?',
    whereArgs: [attendance.id],
  );

  /// 열려 있는 세션에만 하원 시각을 채운다. 바뀐 행 수를 돌려준다.
  ///
  /// 조건을 SQL 안에 두는 이유: 읽고 쓰는 사이에 같은 순간의 다른 요청이 먼저 닫았다면
  /// 0 이 돌아온다. 두 요청이 모두 "방금 하원 처리했다"고 답하면 학부모에게 하원 알림이
  /// 두 번 간다.
  Future<int> closeSession(int id, String checkOutTime) => db.update(
    'attendance',
    {'check_out_time': checkOutTime},
    where: 'id = ? AND check_out_time IS NULL',
    whereArgs: [id],
  );

  /// 등원 시각이 비어 있는 행(자동 결석 처리된 기록)에만 등원을 채운다. 바뀐 행 수를 돌려준다.
  ///
  /// 결석으로 처리된 회원이 실제로 왔을 때 쓴다. [closeSession] 과 같은 이유로 조건을
  /// SQL 안에 둔다.
  Future<int> fillCheckIn(
    int id,
    String checkInTime,
    AttendanceStatus status,
  ) => db.update(
    'attendance',
    {'check_in_time': checkInTime, 'status': status.name},
    where: 'id = ? AND check_in_time IS NULL',
    whereArgs: [id],
  );

  Future<Attendance?> getByMemberAndDate(int memberId, String date) async {
    final rows = await db.query(
      'attendance',
      where: 'member_id = ? AND date = ?',
      whereArgs: [memberId, date],
    );
    if (rows.isEmpty) return null;
    return Attendance.fromMap(rows.first);
  }

  Future<List<Attendance>> getByDate(String date) async {
    final rows = await db.query(
      'attendance',
      where: 'date = ?',
      whereArgs: [date],
    );
    return rows.map(Attendance.fromMap).toList();
  }

  Future<List<Attendance>> getHistoryForMember(int memberId) async {
    final rows = await db.query(
      'attendance',
      where: 'member_id = ?',
      whereArgs: [memberId],
      orderBy: 'date DESC',
    );
    return rows.map(Attendance.fromMap).toList();
  }

  /// 하원 QR 이 닫을 수 있는 세션.
  ///
  /// 하원 시각이 비어 있고 등원 시각이 `now - window` 이후인 기록 중 **등원 시각이 가장
  /// 최근인 것** 하나를 돌려준다. 오래된 쪽을 닫으면 지난 방문에 엉뚱한 하원 시각이 붙고
  /// 학부모 알림까지 잘못 나간다.
  ///
  /// 등원 시각이 없는 행(자동 결석 처리된 기록)은 세션이 아니므로 제외한다.
  Future<Attendance?> findOpenSession(
    int memberId, {
    required DateTime now,
    Duration window = const Duration(hours: 12),
  }) async {
    final rows = await db.query(
      'attendance',
      where:
          'member_id = ? AND check_out_time IS NULL '
          'AND check_in_time IS NOT NULL AND check_in_time >= ?',
      whereArgs: [memberId, now.subtract(window).toIso8601String()],
      orderBy: 'check_in_time DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Attendance.fromMap(rows.first);
  }

  /// [findOpenSession] 과 같은 창에서 가장 최근 세션을 찾는다. **이미 닫힌 것도 포함한다.**
  ///
  /// 하원 QR 을 받았는데 닫을 세션이 없을 때, "등원 기록이 없다"와 "이미 하원했다"를
  /// 구별하는 데 쓴다. 날짜로 찾으면 자정을 넘겨 하원한 사람이 재스캔할 때 어제 날짜에 있는
  /// 자기 기록을 못 찾아 "등원 기록이 없습니다"를 보게 된다.
  Future<Attendance?> findLatestSessionWithin(
    int memberId, {
    required DateTime now,
    Duration window = const Duration(hours: 12),
  }) async {
    final rows = await db.query(
      'attendance',
      where:
          'member_id = ? AND check_in_time IS NOT NULL AND check_in_time >= ?',
      whereArgs: [memberId, now.subtract(window).toIso8601String()],
      orderBy: 'check_in_time DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Attendance.fromMap(rows.first);
  }

  /// 아직 닫히지 않았고 등원으로부터 [window] 가 지나지 않은 세션 — "지금 체류 중".
  ///
  /// 날짜로 거르지 않는다. 자정을 넘긴 방문이 보이지 않으면 안 된다.
  /// [findUnclosedSessions] 와 같은 기준 시각을 쓰되 비교 방향이 반대다(`>=` 대 `<`),
  /// 그래서 열린 세션은 두 메서드 중 정확히 하나에만 나온다.
  Future<List<Attendance>> findOpenSessionsWithin({
    required DateTime now,
    Duration window = const Duration(hours: 12),
  }) async {
    final rows = await db.query(
      'attendance',
      where:
          'check_out_time IS NULL AND check_in_time IS NOT NULL '
          'AND check_in_time >= ?',
      whereArgs: [now.subtract(window).toIso8601String()],
      orderBy: 'check_in_time',
    );
    return rows.map(Attendance.fromMap).toList();
  }

  /// 관리자가 보정해야 할 "미하원" 목록.
  ///
  /// 등원 시각이 있고 하원 시각이 비어 있으며 등원으로부터 `window` 가 지난 기록.
  /// 이 상태는 저장하는 값이 아니라 조회 시 파생된다 — `status` 는 건드리지 않는다.
  Future<List<Attendance>> findUnclosedSessions({
    required DateTime now,
    Duration window = const Duration(hours: 12),
  }) async {
    final rows = await db.query(
      'attendance',
      where:
          'check_out_time IS NULL AND check_in_time IS NOT NULL '
          'AND check_in_time < ?',
      whereArgs: [now.subtract(window).toIso8601String()],
      orderBy: 'check_in_time',
    );
    return rows.map(Attendance.fromMap).toList();
  }
}
