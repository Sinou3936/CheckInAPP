enum AttendanceStatus { present, late, absent }

class Attendance {
  final int? id;
  final int memberId;
  final String date; // "YYYY-MM-DD"
  final String? checkInTime; // ISO8601, null when auto-marked absent
  /// ISO8601. 아직 하원하지 않았으면 null.
  ///
  /// [date] 는 등원한 날짜이므로, 자정을 넘겨 하원한 경우 이 값의 날짜가 [date] 보다
  /// 하루 뒤일 수 있다 — 한 번의 방문은 항상 한 행에 남는다.
  final String? checkOutTime;
  final AttendanceStatus status;

  const Attendance({
    this.id,
    required this.memberId,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    required this.status,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'member_id': memberId,
    'date': date,
    'check_in_time': checkInTime,
    'check_out_time': checkOutTime,
    'status': status.name,
  };

  factory Attendance.fromMap(Map<String, Object?> map) => Attendance(
    id: map['id'] as int?,
    memberId: map['member_id'] as int,
    date: map['date'] as String,
    checkInTime: map['check_in_time'] as String?,
    checkOutTime: map['check_out_time'] as String?,
    status: AttendanceStatus.values.byName(map['status'] as String),
  );
}
