import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/notification_log.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/services/notification_service.dart';

import '../helpers/test_db.dart';

void main() {
  test('등원 시 학부모 연락처를 수신처로 하는 알림이 기록된다', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final logRepo = NotificationLogRepository(db);
    final service = NotificationService(
      memberRepository: memberRepo,
      notifier: RecordingParentNotifier(logRepo),
    );
    final memberId = await memberRepo.insert(
      const Member(name: '홍길동', classId: null, parentContact: '010-1111-2222'),
    );

    await service.onCheckIn(memberId, DateTime(2026, 10, 16, 15, 2));

    final logs = await logRepo.getRecent();
    expect(logs, hasLength(1));
    expect(logs.single.memberId, memberId);
    expect(logs.single.kind, NotificationKind.checkIn);
    expect(logs.single.recipient, '010-1111-2222');
    expect(
      logs.single.occurredAt,
      DateTime(2026, 10, 16, 15, 2).toIso8601String(),
    );
    await db.close();
  });

  test('하원 시에도 알림이 기록된다', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final logRepo = NotificationLogRepository(db);
    final service = NotificationService(
      memberRepository: memberRepo,
      notifier: RecordingParentNotifier(logRepo),
    );
    final memberId = await memberRepo.insert(
      const Member(name: '홍길동', classId: null, parentContact: '010-1111-2222'),
    );

    await service.onCheckOut(memberId, DateTime(2026, 10, 16, 18, 30));

    final logs = await logRepo.getRecent();
    expect(logs.single.kind, NotificationKind.checkOut);
    await db.close();
  });

  test('학부모 연락처가 없어도 알림은 수신처 없이 기록된다', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final logRepo = NotificationLogRepository(db);
    final service = NotificationService(
      memberRepository: memberRepo,
      notifier: RecordingParentNotifier(logRepo),
    );
    final memberId = await memberRepo.insert(
      const Member(name: '무연락', classId: null),
    );

    await service.onCheckIn(memberId, DateTime(2026, 10, 16, 15, 0));

    final logs = await logRepo.getRecent();
    expect(logs, hasLength(1));
    expect(logs.single.recipient, isNull);
    await db.close();
  });

  test('getRecent 는 최신 발생 순으로 돌려준다', () async {
    final db = await openTestDatabase();
    final logRepo = NotificationLogRepository(db);

    await logRepo.insert(
      const NotificationLog(
        memberId: 1,
        occurredAt: '2026-10-16T15:00:00.000',
        kind: NotificationKind.checkIn,
      ),
    );
    await logRepo.insert(
      const NotificationLog(
        memberId: 1,
        occurredAt: '2026-10-16T18:00:00.000',
        kind: NotificationKind.checkOut,
      ),
    );

    final logs = await logRepo.getRecent();
    expect(logs.first.kind, NotificationKind.checkOut);
    expect(logs.last.kind, NotificationKind.checkIn);
    await db.close();
  });
}
