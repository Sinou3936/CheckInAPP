import 'package:checkin_app/models/attendance.dart';

/// 출결 상태를 화면에 보일 한글 라벨로 바꾼다. 화면마다 따로 적으면 서로 갈라지므로 이 한 곳에 둔다.
String attendanceStatusLabel(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => '출석',
  AttendanceStatus.late => '지각',
  AttendanceStatus.absent => '결석',
};

// ── 파생 표시: 상태가 아니다 ───────────────────────────────────────────────
//
// 아래 두 표시는 `AttendanceStatus` 가 아니다. DB 에 저장하지 않고 조회 시 파생한다.
// 둘 다 "등원 시각이 있고 하원 시각이 없는" 기록을 가리키지만, 등원으로부터 경과 시간으로 갈린다.
// 경계(12시간)는 AttendanceRepository 가 정하며 화면은 그 결과 집합을 따르기만 한다.
//
// - 체류 중: 등원으로부터 12시간 이내. 아직 하원 QR 로 닫을 수 있다. 정상이며 관리자가 할 일이 없다.
//   `findOpenSessionsWithin` 의 결과다.
// - 미하원: 등원으로부터 12시간 경과. 하원 QR 로는 더 닫을 수 없으므로 관리자가 이력 화면에서
//   보정해야 한다(보정 대상). `findUnclosedSessions` 의 결과다.

/// 등원 후 12시간 이내이고 아직 하원하지 않은 기록에 붙이는 라벨.
const stayingLabel = '체류 중';

/// 등원 후 12시간이 지나도록 하원하지 않은 기록(보정 대상)에 붙이는 라벨.
const overdueLabel = '미하원';
