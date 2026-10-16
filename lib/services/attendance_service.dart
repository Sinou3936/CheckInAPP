import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';

enum CheckInStatus { recorded, alreadyCheckedIn }

enum CheckOutStatus { recorded, noOpenSession, alreadyCheckedOut }

class CheckInOutcome {
  final CheckInStatus status;
  final Attendance attendance;

  const CheckInOutcome(this.status, this.attendance);
}

class CheckOutOutcome {
  final CheckOutStatus status;

  /// `recorded` 면 하원 시각이 채워진 기록, `alreadyCheckedOut` 이면 이미 닫혀 있던 기록.
  /// `noOpenSession` 이면 null.
  final Attendance? attendance;

  const CheckOutOutcome(this.status, this.attendance);
}

/// 출결 기록의 규칙을 담은 서비스.
///
/// 등원과 하원을 **추론하지 않는다** — 학생이 어느 QR 을 스캔했는지가 호출할 메서드를
/// 결정한다. 등원 QR 을 여러 번 스캔해도 하원으로 넘어가지 않으므로, 거짓 하원 알림이
/// 구조적으로 생기지 않는다.
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
    if (existing != null) {
      return CheckInOutcome(CheckInStatus.alreadyCheckedIn, existing);
    }

    final member = await memberRepository.getById(memberId);
    if (member == null) {
      throw ArgumentError('Unknown member id: $memberId');
    }

    var status = AttendanceStatus.present;
    if (member.classId != null) {
      final classModel = await classRepository.getById(member.classId!);
      if (classModel != null) {
        status = determineStatus(
          classModel.startDateTimeFor(checkInTime),
          checkInTime,
        );
      }
    }

    await attendanceRepository.insert(
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
    return CheckInOutcome(CheckInStatus.recorded, stored!);
  }

  /// 하원 QR 을 스캔했을 때.
  ///
  /// [checkOutWindow] 이내의 열린 세션 중 등원이 가장 최근인 것을 닫는다. 세션은 등원한
  /// 날짜의 행에 귀속되므로, 자정을 넘겨 하원해도 새 행이 생기지 않는다.
  Future<CheckOutOutcome> recordCheckOut(int memberId, {DateTime? now}) async {
    final checkOutTime = now ?? DateTime.now();

    final open = await attendanceRepository.findOpenSession(
      memberId,
      now: checkOutTime,
      window: checkOutWindow,
    );
    if (open != null) {
      await attendanceRepository.update(
        Attendance(
          id: open.id,
          memberId: open.memberId,
          date: open.date,
          checkInTime: open.checkInTime,
          checkOutTime: checkOutTime.toIso8601String(),
          status: open.status,
        ),
      );
      final stored = await attendanceRepository.getByMemberAndDate(
        memberId,
        open.date,
      );
      return CheckOutOutcome(CheckOutStatus.recorded, stored);
    }

    final today = await attendanceRepository.getByMemberAndDate(
      memberId,
      formatDate(checkOutTime),
    );
    if (today != null && today.checkOutTime != null) {
      return CheckOutOutcome(CheckOutStatus.alreadyCheckedOut, today);
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
