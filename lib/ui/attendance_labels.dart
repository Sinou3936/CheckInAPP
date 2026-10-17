import 'package:checkin_app/models/attendance.dart';

/// 출결 상태를 화면에 보일 한글 라벨로 바꾼다. 화면마다 따로 적으면 서로 갈라지므로 이 한 곳에 둔다.
///
/// `미하원` 은 여기 속하지 않는다. 상태가 아니라 조회 시 파생되는 표시다 — `checkInTime` 이 있고
/// `checkOutTime` 이 없을 때 화면이 보여준다. DB 에는 저장하지 않는다.
String attendanceStatusLabel(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => '출석',
  AttendanceStatus.late => '지각',
  AttendanceStatus.absent => '결석',
};
