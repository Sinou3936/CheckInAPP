import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/notification_log.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/ui/screens/audit_log_screen.dart';

import '../helpers/test_db.dart';
import '../helpers/widget_test_helpers.dart';

Future<void> pumpScreen(
  WidgetTester tester, {
  required Future<void> Function(
    MemberRepository members,
    DeviceBindingRepository devices,
    NotificationLogRepository notifications,
  ) seed,
}) async {
  final db = (await tester.runAsync(openTestDatabase))!;
  addTearDown(() => db.close());
  final members = MemberRepository(db);
  final devices = DeviceBindingRepository(db);
  final notifications = NotificationLogRepository(db);
  await tester.runAsync(() => seed(members, devices, notifications));
  await tester.pumpWidget(
    MaterialApp(
      home: AuditLogScreen(
        deviceBindingRepository: devices,
        notificationLogRepository: notifications,
        memberRepository: members,
      ),
    ),
  );
  await pumpUntil(tester, () => absent(find.byType(CircularProgressIndicator)));
}

void main() {
  testWidgets('이력이 없으면 각 탭이 빈 안내를 보인다', (tester) async {
    await pumpScreen(tester, seed: (_, __, ___) async {});
    expect(find.text('알림 내역이 없습니다.'), findsOneWidget);

    await tester.tap(find.text('바인딩 이력'));
    await tester.pumpAndSettle();
    expect(find.text('바인딩 이력이 없습니다.'), findsOneWidget);
  });

  testWidgets('알림 내역에 회원 이름, 종류, 수신처가 보이고 연락처가 없으면 대상 없음이 보인다',
      (tester) async {
    await pumpScreen(tester, seed: (members, _, notifications) async {
      final a = await members.insert(Member(name: '김철수'));
      final b = await members.insert(Member(name: '이영희'));
      await notifications.insert(NotificationLog(
        memberId: a,
        occurredAt: DateTime(2026, 10, 1, 15, 5).toIso8601String(),
        kind: NotificationKind.checkIn,
        recipient: '010-1111-2222',
      ));
      await notifications.insert(NotificationLog(
        memberId: b,
        occurredAt: DateTime(2026, 10, 1, 17, 0).toIso8601String(),
        kind: NotificationKind.checkOut,
      ));
    });

    expect(find.text('김철수 · 등원'), findsOneWidget);
    expect(find.textContaining('수신처 010-1111-2222'), findsOneWidget);
    expect(find.text('이영희 · 하원'), findsOneWidget);
    expect(find.textContaining('알림 대상 없음'), findsOneWidget);
  });

  testWidgets('같은 기기가 다른 회원으로 묶인 이력에는 경고가 붙는다', (tester) async {
    await pumpScreen(tester, seed: (members, devices, _) async {
      final a = await members.insert(Member(name: '김철수'));
      final b = await members.insert(Member(name: '이영희'));
      await devices.bind('device-shared', a, now: DateTime(2026, 10, 1, 9));
      await devices.bind('device-shared', b, now: DateTime(2026, 10, 2, 9));
      await devices.bind('device-solo', a, now: DateTime(2026, 10, 3, 9));
    });
    await tester.tap(find.text('바인딩 이력'));
    await tester.pumpAndSettle();

    // 공유 기기의 두 행에만 경고 문구가 붙는다.
    expect(find.textContaining('다른 회원으로도 묶인 기기'), findsNWidgets(2));
    expect(find.byIcon(Icons.warning_amber), findsNWidgets(2));
    expect(find.byIcon(Icons.phone_android), findsOneWidget);
  });

  testWidgets('삭제된 회원의 이력은 번호로 보인다', (tester) async {
    await pumpScreen(tester, seed: (_, devices, __) async {
      await devices.bind('device-1', 99, now: DateTime(2026, 10, 1, 9));
    });
    await tester.tap(find.text('바인딩 이력'));
    await tester.pumpAndSettle();
    expect(find.text('삭제된 회원 (#99)'), findsOneWidget);
  });
}
