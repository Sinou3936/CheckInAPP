import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/check_kind.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';

enum CheckInStatus { recorded, alreadyCheckedIn }

enum CheckOutStatus { recorded, noOpenSession, alreadyCheckedOut, tooEarly }

/// 한 번의 스캔에 대해 서버가 내리는 판정. 설계 문서의 판정표 1~8번과 1:1 로 대응한다.
enum CheckAction {
  /// 1·2번. 등원으로 기록할 수 있다.
  checkIn,

  /// 3번. 하원으로 기록할 수 있다.
  checkOut,

  /// 8번. 날짜 경계라서 등원과 하원이 둘 다 현실적으로 가능하다 — 학생에게 묻는다.
  choice,

  /// 4·7번. 최소 체류 시간이 지나지 않았다. 아무것도 기록하지 않는다.
  tooEarly,

  /// 5번. 등원으로부터 하원 창(12시간)이 지났다. 관리자 보정 대상이다.
  overdue,

  /// 6번. 오늘 행이 이미 닫혀 있다.
  alreadyCheckedOut,
}

/// 판정 결과와 그 근거.
class CheckJudgment {
  final CheckAction action;

  /// [CheckAction.tooEarly] 에서만 채운다. 하원까지 남은 시간.
  final Duration? remaining;

  /// 판정의 근거가 된 행. [CheckAction.checkIn] 에서는 null.
  final Attendance? openSession;

  const CheckJudgment(this.action, {this.remaining, this.openSession});

  /// 쓰기 시점 재판정이 이 집합으로 허용 여부를 본다. 비어 있으면 아무것도 기록하지 않는다.
  Set<CheckKind> get allowedKinds => switch (action) {
    CheckAction.checkIn => const {CheckKind.checkIn},
    CheckAction.checkOut => const {CheckKind.checkOut},
    CheckAction.choice => const {CheckKind.checkIn, CheckKind.checkOut},
    CheckAction.tooEarly ||
    CheckAction.overdue ||
    CheckAction.alreadyCheckedOut => const {},
  };
}

class CheckInOutcome {
  final CheckInStatus status;
  final Attendance attendance;

  const CheckInOutcome(this.status, this.attendance);
}

class CheckOutOutcome {
  final CheckOutStatus status;

  /// `recorded` 면 하원 시각이 채워진 기록, `alreadyCheckedOut` 이면 이미 닫혀 있던 기록,
  /// `tooEarly` 면 아직 닫지 않은 그 세션. `noOpenSession` 이면 null.
  final Attendance? attendance;

  const CheckOutOutcome(this.status, this.attendance);
}

/// 출결 기록의 규칙을 담은 서비스.
///
/// QR 이 하나이므로 등원인지 하원인지는 **회원의 상태에서** 나온다 ([judge]). 등원 직후의
/// 재스캔이 거짓 하원이 되는 것은 **최소 체류 시간**이 막는다 — 예전에는 QR 을 둘로 나눠
/// 막았고, 2026-10-27 개정이 그 결정을 대체했다.
///
/// **이 서비스는 학부모 알림을 발생시키지 않는다.** 알림은 학생이 QR 을 스캔하는 경로에서만
/// 나가야 하고 관리자 보정은 저장소를 직접 쓰므로, 알림 호출은 결과를 보고 판단할 수 있는
/// 서버 엔드포인트가 담당한다. 그래서 두 기록 메서드는 "새로 기록했는지"를 담은 결과 객체를
/// 돌려준다.
class AttendanceService {
  final MemberRepository memberRepository;
  final ClassRepository classRepository;
  final AttendanceRepository attendanceRepository;

  /// 반 시작 시각 이후 이 시간까지는 출석, 넘기면 지각.
  final Duration gracePeriod;

  /// 하원 QR 이 닫을 수 있는 열린 세션의 최대 경과 시간.
  final Duration checkOutWindow;

  AttendanceService({
    required this.memberRepository,
    required this.classRepository,
    required this.attendanceRepository,
    this.gracePeriod = const Duration(minutes: 10),
    this.checkOutWindow = const Duration(hours: 12),
  });

  static String formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// 이 스캔이 등원인지 하원인지, 아니면 막아야 하는지 판정한다.
  ///
  /// **오늘 날짜의 행을 먼저 보고, 오늘 행이 없을 때만 12시간 창을 본다.** 이 순서가
  /// 핵심이다. 두 개념을 섞으면 어제 23:50 에 등원하고 하원을 안 찍은 학생이 오늘 08:00 에
  /// 스캔할 때 그것을 하원으로 판정해, 어제 행에 08:00 하원이 붙고 **학부모에게 거짓 하원
  /// 알림**이 가며 오늘 등원은 기록되지 않는다.
  Future<CheckJudgment> judge(
    int memberId, {
    required Duration minimumStay,
    DateTime? now,
  }) async {
    final checkTime = now ?? DateTime.now();
    final todayRow = await attendanceRepository.getByMemberAndDate(
      memberId,
      formatDate(checkTime),
    );

    final todayCheckIn = todayRow?.checkInTime;
    if (todayRow != null && todayCheckIn != null) {
      if (todayRow.checkOutTime != null) {
        return CheckJudgment(
          CheckAction.alreadyCheckedOut,
          openSession: todayRow,
        );
      }
      return _judgeOpenSession(todayRow, todayCheckIn, checkTime, minimumStay);
    }

    // 오늘 행이 없거나 등원 시각이 비어 있다(자동 결석 행). 둘 다 등원을 받을 상태다.
    if (todayRow != null) return const CheckJudgment(CheckAction.checkIn);

    final open = await attendanceRepository.findOpenSession(
      memberId,
      now: checkTime,
      window: checkOutWindow,
    );
    if (open == null) return const CheckJudgment(CheckAction.checkIn);

    // 이전 날짜의 열린 세션이 창 안에 있다. 자정을 넘겨 나가는 중일 수도, 오늘 새로
    // 등원하는 중일 수도 있다 — 경과 시간만으로는 구별되지 않아 학생에게 묻는다.
    return _judgeOpenSession(
      open,
      open.checkInTime!,
      checkTime,
      minimumStay,
      crossesDate: true,
    );
  }

  /// 열린 세션 하나에 대한 판정. 창 지남 → 미경과 → 하원(또는 선택) 순으로 본다.
  CheckJudgment _judgeOpenSession(
    Attendance open,
    String checkInTime,
    DateTime now,
    Duration minimumStay, {
    bool crossesDate = false,
  }) {
    final elapsed = now.difference(DateTime.parse(checkInTime));
    if (!crossesDate && elapsed >= checkOutWindow) {
      return CheckJudgment(CheckAction.overdue, openSession: open);
    }
    if (elapsed < minimumStay) {
      return CheckJudgment(
        CheckAction.tooEarly,
        remaining: minimumStay - elapsed,
        openSession: open,
      );
    }
    return CheckJudgment(
      crossesDate ? CheckAction.choice : CheckAction.checkOut,
      openSession: open,
    );
  }

  AttendanceStatus determineStatus(DateTime classStart, DateTime checkInTime) {
    return checkInTime.isAfter(classStart.add(gracePeriod))
        ? AttendanceStatus.late
        : AttendanceStatus.present;
  }

  /// 등원 QR 을 스캔했을 때.
  ///
  /// 그날 이미 등원 기록이 있으면 아무것도 쓰지 않고 [CheckInStatus.alreadyCheckedIn] 과
  /// 기존 기록을 돌려준다. 한 회원은 하루에 한 번만 등원한다.
  Future<CheckInOutcome> recordCheckIn(int memberId, {DateTime? now}) async {
    final checkInTime = now ?? DateTime.now();
    final dateKey = formatDate(checkInTime);

    final existing = await attendanceRepository.getByMemberAndDate(
      memberId,
      dateKey,
    );
    if (existing != null && existing.checkInTime != null) {
      return CheckInOutcome(CheckInStatus.alreadyCheckedIn, existing);
    }

    final member = await memberRepository.getById(memberId);
    if (member == null) {
      throw ArgumentError('Unknown member id: $memberId');
    }
    final status = await _statusFor(member.classId, checkInTime);

    // 자동 결석 처리된 행이 이미 있으면(등원 시각 없음) 등원으로 올린다 — 결석으로
    // 찍혔다는 이유로 실제로 온 회원의 등원을 못 받으면, 그 회원은 하루 종일 결석이고
    // 학부모 알림도 나가지 않는다.
    if (existing != null) {
      final filled = await attendanceRepository.fillCheckIn(
        existing.id!,
        checkInTime.toIso8601String(),
        status,
      );
      final stored = await attendanceRepository.getByMemberAndDate(
        memberId,
        dateKey,
      );
      return CheckInOutcome(
        filled == 0 ? CheckInStatus.alreadyCheckedIn : CheckInStatus.recorded,
        stored!,
      );
    }

    final insertedId = await attendanceRepository.insert(
      Attendance(
        memberId: memberId,
        date: dateKey,
        checkInTime: checkInTime.toIso8601String(),
        status: status,
      ),
    );
    final stored = await attendanceRepository.getByMemberAndDate(
      memberId,
      dateKey,
    );
    // 0 이면 같은 순간의 다른 요청이 먼저 기록했다는 뜻이다 (UNIQUE 충돌로 무시됨).
    // 두 요청이 모두 recorded 로 답하면 학부모에게 알림이 두 번 간다.
    return CheckInOutcome(
      insertedId == 0 ? CheckInStatus.alreadyCheckedIn : CheckInStatus.recorded,
      stored!,
    );
  }

  Future<AttendanceStatus> _statusFor(
    int? classId,
    DateTime checkInTime,
  ) async {
    if (classId == null) return AttendanceStatus.present;
    final classModel = await classRepository.getById(classId);
    if (classModel == null) return AttendanceStatus.present;
    return determineStatus(
      classModel.startDateTimeFor(checkInTime),
      checkInTime,
    );
  }

  /// 하원으로 판정된 스캔을 기록한다.
  ///
  /// [checkOutWindow] 이내의 열린 세션 중 등원이 가장 최근인 것을 닫는다. 세션은 등원한
  /// 날짜의 행에 귀속되므로, 자정을 넘겨 하원해도 새 행이 생기지 않는다.
  ///
  /// 등원으로부터 [minimumStay] 가 지나지 않았으면 **아무것도 쓰지 않고**
  /// [CheckOutStatus.tooEarly] 를 돌려준다. 호출 전에 [judge] 가 이미 막지만, 판정을
  /// 건너뛴 호출자가 생겨도 거짓 하원이 새지 않게 여기서도 본다.
  Future<CheckOutOutcome> recordCheckOut(
    int memberId, {
    required Duration minimumStay,
    DateTime? now,
  }) async {
    final checkOutTime = now ?? DateTime.now();

    final open = await attendanceRepository.findOpenSession(
      memberId,
      now: checkOutTime,
      window: checkOutWindow,
    );
    if (open != null) {
      final elapsed = checkOutTime.difference(
        DateTime.parse(open.checkInTime!),
      );
      if (elapsed < minimumStay) {
        return CheckOutOutcome(CheckOutStatus.tooEarly, open);
      }
      final closed = await attendanceRepository.closeSession(
        open.id!,
        checkOutTime.toIso8601String(),
      );
      final stored = await attendanceRepository.getByMemberAndDate(
        memberId,
        open.date,
      );
      // 0 이면 같은 순간의 다른 요청이 먼저 닫았다는 뜻이다. 두 요청이 모두 recorded 로
      // 답하면 학부모에게 하원 알림이 두 번 간다.
      return CheckOutOutcome(
        closed == 0
            ? CheckOutStatus.alreadyCheckedOut
            : CheckOutStatus.recorded,
        stored,
      );
    }

    // 닫을 세션이 없다. "등원 기록이 없다"와 "이미 하원했다"를 **열린 세션과 같은 창에서**
    // 구별한다 — 오늘 날짜로만 찾으면 자정을 넘겨 하원한 사람이 재스캔할 때 어제 날짜에
    // 있는 자기 기록을 못 찾아 "등원 기록이 없습니다"를 보게 된다.
    final latest = await attendanceRepository.findLatestSessionWithin(
      memberId,
      now: checkOutTime,
      window: checkOutWindow,
    );
    if (latest != null && latest.checkOutTime != null) {
      return CheckOutOutcome(CheckOutStatus.alreadyCheckedOut, latest);
    }
    return const CheckOutOutcome(CheckOutStatus.noOpenSession, null);
  }

  /// 운영 요일에 체크 기록이 없는 소속 회원을 결석 처리한다. 처리한 건수를 돌려준다.
  ///
  /// 운영 요일이 아닌 날에는 아무것도 하지 않으므로, 그런 날 들어온 체크인은 그대로 정상
  /// 출석 기록으로 남는다.
  Future<int> markAbsentees(DateTime date) async {
    final dateKey = formatDate(date);
    final classes = await classRepository.getAll();
    var markedCount = 0;
    for (final classModel in classes) {
      if (classModel.id == null || !classModel.operatesOn(date)) continue;
      final members = await memberRepository.getByClassId(classModel.id!);
      for (final member in members) {
        if (member.id == null) continue;
        final existing = await attendanceRepository.getByMemberAndDate(
          member.id!,
          dateKey,
        );
        if (existing != null) continue;
        await attendanceRepository.insert(
          Attendance(
            memberId: member.id!,
            date: dateKey,
            checkInTime: null,
            status: AttendanceStatus.absent,
          ),
        );
        markedCount++;
      }
    }
    return markedCount;
  }
}
