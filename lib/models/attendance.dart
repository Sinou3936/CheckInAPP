enum AttendanceStatus { present, late, absent }

class Attendance {
  final int? id;
  final int memberId;
  final String date; // "YYYY-MM-DD"
  final String? checkInTime; // ISO8601, null when auto-marked absent
  final AttendanceStatus status;

  const Attendance({
    this.id,
    required this.memberId,
    required this.date,
    this.checkInTime,
    required this.status,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'member_id': memberId,
    'date': date,
    'check_in_time': checkInTime,
    'status': status.name,
  };

  factory Attendance.fromMap(Map<String, Object?> map) => Attendance(
    id: map['id'] as int?,
    memberId: map['member_id'] as int,
    date: map['date'] as String,
    checkInTime: map['check_in_time'] as String?,
    status: AttendanceStatus.values.byName(map['status'] as String),
  );
}
