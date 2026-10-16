import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/device_binding.dart';
import 'package:checkin_app/models/notification_log.dart';
import 'package:checkin_app/models/binding_log.dart';

void main() {
  test('Member 는 학부모 연락처를 포함해 왕복한다', () {
    const member = Member(
      id: 1,
      name: '홍길동',
      classId: 2,
      parentContact: '010-0000-0000',
    );
    final restored = Member.fromMap(member.toMap());
    expect(restored.id, 1);
    expect(restored.name, '홍길동');
    expect(restored.classId, 2);
    expect(restored.parentContact, '010-0000-0000');
  });

  test('Member 는 학부모 연락처가 없어도 왕복한다', () {
    const member = Member(id: 1, name: '홍길동', classId: null);
    expect(Member.fromMap(member.toMap()).parentContact, isNull);
  });

  test('copyWith 는 clearParentContact 로 연락처를 지운다', () {
    const member = Member(id: 1, name: '홍길동', parentContact: '010-0000-0000');
    expect(member.copyWith(clearParentContact: true).parentContact, isNull);
    expect(member.copyWith(name: '김철수').parentContact, '010-0000-0000');
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

  test('Attendance 는 결석 기록(등원 시각 null)으로 왕복한다', () {
    const attendance = Attendance(
      id: 1,
      memberId: 5,
      date: '2026-09-18',
      checkInTime: null,
      checkOutTime: null,
      status: AttendanceStatus.absent,
    );
    final restored = Attendance.fromMap(attendance.toMap());
    expect(restored.memberId, 5);
    expect(restored.checkInTime, isNull);
    expect(restored.checkOutTime, isNull);
    expect(restored.status, AttendanceStatus.absent);
  });

  test('Attendance 는 하원 전 상태(하원 시각 null)로 왕복한다', () {
    const attendance = Attendance(
      id: 1,
      memberId: 5,
      date: '2026-10-16',
      checkInTime: '2026-10-16T15:02:00.000',
      checkOutTime: null,
      status: AttendanceStatus.present,
    );
    final restored = Attendance.fromMap(attendance.toMap());
    expect(restored.checkInTime, '2026-10-16T15:02:00.000');
    expect(restored.checkOutTime, isNull);
  });

  test('Attendance 는 자정을 넘긴 하원 시각도 그대로 왕복한다', () {
    const attendance = Attendance(
      id: 1,
      memberId: 5,
      date: '2026-10-16',
      checkInTime: '2026-10-16T23:50:00.000',
      checkOutTime: '2026-10-17T00:20:00.000',
      status: AttendanceStatus.present,
    );
    final restored = Attendance.fromMap(attendance.toMap());
    expect(restored.date, '2026-10-16');
    expect(restored.checkOutTime, '2026-10-17T00:20:00.000');
  });

  test('DeviceBinding 은 바인딩 시각을 포함해 왕복한다', () {
    const binding = DeviceBinding(
      id: 1,
      deviceToken: 'abc123',
      memberId: 7,
      boundAt: '2026-10-16T15:00:00.000',
    );
    final restored = DeviceBinding.fromMap(binding.toMap());
    expect(restored.deviceToken, 'abc123');
    expect(restored.memberId, 7);
    expect(restored.boundAt, '2026-10-16T15:00:00.000');
  });

  test('NotificationLog 는 왕복한다', () {
    const log = NotificationLog(
      id: 1,
      memberId: 7,
      occurredAt: '2026-10-16T18:30:00.000',
      kind: NotificationKind.checkOut,
      recipient: '010-0000-0000',
    );
    final restored = NotificationLog.fromMap(log.toMap());
    expect(restored.memberId, 7);
    expect(restored.kind, NotificationKind.checkOut);
    expect(restored.recipient, '010-0000-0000');
  });

  test('BindingLog 는 왕복한다', () {
    const log = BindingLog(
      id: 1,
      deviceToken: 'abc123',
      memberId: 7,
      occurredAt: '2026-10-16T15:00:00.000',
    );
    final restored = BindingLog.fromMap(log.toMap());
    expect(restored.deviceToken, 'abc123');
    expect(restored.memberId, 7);
    expect(restored.occurredAt, '2026-10-16T15:00:00.000');
  });
}
