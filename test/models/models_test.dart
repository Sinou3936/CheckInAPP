import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/device_binding.dart';

void main() {
  test('Member round-trips through toMap/fromMap', () {
    const member = Member(id: 1, name: '홍길동', classId: 2);
    final restored = Member.fromMap(member.toMap());
    expect(restored.id, 1);
    expect(restored.name, '홍길동');
    expect(restored.classId, 2);
  });

  test('ClassModel round-trips and reports operating days correctly', () {
    final classModel = ClassModel(
      id: 1,
      name: '국어반',
      startTime: '15:00',
      operatingDays: {1, 3, 5}, // Mon/Wed/Fri
    );
    final restored = ClassModel.fromMap(classModel.toMap());
    expect(restored.name, '국어반');
    expect(restored.startTime, '15:00');
    expect(restored.operatingDays, {1, 3, 5});
    expect(restored.operatesOn(DateTime(2026, 9, 21)), isTrue); // Monday
    expect(restored.operatesOn(DateTime(2026, 9, 22)), isFalse); // Tuesday
    final start = restored.startDateTimeFor(DateTime(2026, 9, 21));
    expect(start, DateTime(2026, 9, 21, 15, 0));
  });

  test('Attendance round-trips including null checkInTime', () {
    const attendance = Attendance(
      id: 1,
      memberId: 5,
      date: '2026-09-18',
      checkInTime: null,
      status: AttendanceStatus.absent,
    );
    final restored = Attendance.fromMap(attendance.toMap());
    expect(restored.memberId, 5);
    expect(restored.checkInTime, isNull);
    expect(restored.status, AttendanceStatus.absent);
  });

  test('DeviceBinding round-trips', () {
    const binding = DeviceBinding(id: 1, deviceToken: 'abc123', memberId: 7);
    final restored = DeviceBinding.fromMap(binding.toMap());
    expect(restored.deviceToken, 'abc123');
    expect(restored.memberId, 7);
  });
}
