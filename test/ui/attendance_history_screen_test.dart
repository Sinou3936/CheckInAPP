import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/notification_log.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/ui/screens/attendance_history_screen.dart';

import '../helpers/test_db.dart';
import '../helpers/widget_test_helpers.dart';

const _timeError = '시각을 HH:mm 형식으로 입력하세요 (예: 09:00)';
const _orderError = '등원 시각 없이 하원 시각을 넣을 수 없습니다';

class Harness {
  final AttendanceRepository attendance;
  final MemberRepository members;
  final NotificationLogRepository notifications;
  int memberId = 0;

  Harness(this.attendance, this.members, this.notifications);
}

/// [seed] 는 시드한 회원의 id 를 돌려준다. 화면은 그 회원을 이름으로 골라서 쓴다.
Future<Harness> pumpScreen(
  WidgetTester tester,
  Future<int> Function(Harness h) seed,
) async {
  final db = (await tester.runAsync(openTestDatabase))!;
  addTearDown(() => db.close());
  final h = Harness(
    AttendanceRepository(db),
    MemberRepository(db),
    NotificationLogRepository(db),
  );
  h.memberId = (await tester.runAsync(() => seed(h)))!;
  await tester.pumpWidget(
    MaterialApp(
      home: AttendanceHistoryScreen(
        memberRepository: h.members,
        attendanceRepository: h.attendance,
      ),
    ),
  );
  await pumpUntil(tester, () => absent(find.byType(CircularProgressIndicator)));
  return h;
}

Future<int> addMember(Harness h, String name) =>
    h.members.insert(Member(name: name));

/// 테스트 데이터의 날짜는 `YYYY-MM-DD` 로 맞춘다. 행 날짜는 등원한 날짜여야 한다.
String dateKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// 날짜 문자열로 그 날짜의 목록 행(ListTile)을 찾는다.
Finder rowOf(String date) =>
    find.ancestor(of: find.text(date), matching: find.byType(ListTile));

Finder editButtonOf(String date) =>
    find.descendant(of: rowOf(date), matching: find.byTooltip('보정'));

Finder get summaryText => find.byKey(const Key('summaryText'));

Future<void> selectMember(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('memberDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  // 회원을 바꾸면 기록을 다시 읽는 동안 로딩 표시가 잠깐 뜨므로 pumpAndSettle 을 쓰지 않는다.
  await tester.pump();
  await pumpUntil(tester, () => absent(find.byType(CircularProgressIndicator)));
}

Future<void> selectMonth(WidgetTester tester, String month) async {
  await tester.tap(find.byKey(const Key('monthDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(month).last);
  await tester.pumpAndSettle();
}

Future<void> openEdit(WidgetTester tester, String date) async {
  await tester.tap(editButtonOf(date));
  await tester.pumpAndSettle();
}

Future<void> typeIn(WidgetTester tester, String key, String text) =>
    tester.enterText(find.byKey(Key(key)), text);

/// 입력칸의 현재 글자. 보정 양식이 기존 값을 채워 열렸는지 확인할 때 쓴다.
String fieldText(WidgetTester tester, String key) {
  final editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(EditableText),
    ),
  );
  return editable.controller.text;
}

/// 저장은 다이얼로그를 닫은 뒤에야 DB 쓰기와 목록 재조회를 시작한다. 다이얼로그가 닫히고
/// [listed] 가 보여야 재조회까지 끝난 것이다.
Future<void> save(WidgetTester tester, Finder listed) async {
  await tester.tap(find.widgetWithText(FilledButton, '저장'));
  await pumpUntil(
    tester,
    () => absent(find.byType(AlertDialog)) && shown(listed),
  );
  expect(find.byType(AlertDialog), findsNothing);
}

Future<Attendance> savedRow(WidgetTester tester, Harness h, String date) async {
  final row = await tester.runAsync(
    () => h.attendance.getByMemberAndDate(h.memberId, date),
  );
  return row!;
}

void main() {
  testWidgets('첫 로드 전에는 로딩 표시만 보이고 회원 선택 안내는 보이지 않는다', (tester) async {
    final db = (await tester.runAsync(openTestDatabase))!;
    addTearDown(() => db.close());
    await tester.runAsync(
      () => MemberRepository(db).insert(const Member(name: '김회원')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceHistoryScreen(
          memberRepository: MemberRepository(db),
          attendanceRepository: AttendanceRepository(db),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('회원을 선택하세요'), findsNothing);

    await pumpUntil(
      tester,
      () => absent(find.byType(CircularProgressIndicator)),
    );
    expect(find.text('회원을 선택하세요'), findsOneWidget);
  });

  testWidgets('회원을 고르기 전에는 기록 목록이 보이지 않는다', (tester) async {
    await pumpScreen(tester, (h) => addMember(h, '김회원'));

    expect(find.byType(ListTile), findsNothing);
    expect(find.text('김회원'), findsNothing);
  });

  testWidgets('기록은 날짜별로 상태와 등원·하원 시각을 보여주고, 자동 결석 행에는 시각을 그리지 않는다', (
    tester,
  ) async {
    await pumpScreen(tester, (h) async {
      final id = await addMember(h, '이기록');
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: '2020-01-10',
          checkInTime: DateTime(2020, 1, 10, 9, 0).toIso8601String(),
          checkOutTime: DateTime(2020, 1, 10, 18, 0).toIso8601String(),
          status: AttendanceStatus.present,
        ),
      );
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: '2020-01-09',
          status: AttendanceStatus.absent,
        ),
      );
      return id;
    });
    await selectMember(tester, '이기록');

    expect(inRow(find.text('출석')), findsOneWidget);
    expect(inRow(find.text('등원 09:00 · 하원 18:00')), findsOneWidget);

    expect(inRow(find.text('결석')), findsOneWidget);
    expect(
      find.descendant(
        of: rowOf('2020-01-09'),
        matching: find.textContaining('등원'),
      ),
      findsNothing,
    );
  });

  testWidgets('기록이 없는 회원은 안내를 보여준다', (tester) async {
    await pumpScreen(tester, (h) => addMember(h, '빈회원'));
    await selectMember(tester, '빈회원');

    expect(find.text('출결 기록이 없습니다.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('자정을 넘긴 하원을 보정하면 하원 시각은 다음 날로 저장되고 다음 날임을 표시한다', (tester) async {
    final h = await pumpScreen(tester, (h) async {
      final id = await addMember(h, '김자정');
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: '2020-01-10',
          checkInTime: DateTime(2020, 1, 10, 23, 50).toIso8601String(),
          status: AttendanceStatus.present,
        ),
      );
      return id;
    });
    await selectMember(tester, '김자정');
    expect(inRow(find.text('등원 23:50 · 하원 없음')), findsOneWidget);

    await openEdit(tester, '2020-01-10');
    expect(fieldText(tester, 'checkInField'), '23:50');
    await typeIn(tester, 'checkOutField', '00:20');
    await save(tester, inRow(find.text('등원 23:50 · 하원 00:20 (다음 날)')));

    final saved = await savedRow(tester, h, '2020-01-10');
    expect(saved.date, '2020-01-10');
    expect(saved.checkInTime, DateTime(2020, 1, 10, 23, 50).toIso8601String());
    final checkOut = DateTime.parse(saved.checkOutTime!);
    expect(checkOut.year, 2020);
    expect(checkOut.month, 1);
    expect(checkOut.day, 11);
    expect(checkOut.hour, 0);
    expect(checkOut.minute, 20);
    expect(inRow(find.text('미하원')), findsNothing);
  });

  testWidgets('하원 시각을 비우고 저장하면 null 로 저장되고 미하원으로 되돌아간다', (tester) async {
    final h = await pumpScreen(tester, (h) async {
      final id = await addMember(h, '김하원');
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: '2020-01-10',
          checkInTime: DateTime(2020, 1, 10, 9, 0).toIso8601String(),
          checkOutTime: DateTime(2020, 1, 10, 18, 0).toIso8601String(),
          status: AttendanceStatus.present,
        ),
      );
      return id;
    });
    await selectMember(tester, '김하원');
    expect(inRow(find.text('등원 09:00 · 하원 18:00')), findsOneWidget);
    expect(inRow(find.text('미하원')), findsNothing);

    await openEdit(tester, '2020-01-10');
    expect(fieldText(tester, 'checkOutField'), '18:00');
    await typeIn(tester, 'checkOutField', '');
    await save(tester, inRow(find.text('등원 09:00 · 하원 없음')));

    final saved = await savedRow(tester, h, '2020-01-10');
    expect(saved.checkOutTime, isNull);
    expect(inRow(find.text('미하원')), findsOneWidget);
  });

  testWidgets('보정으로 상태를 바꾸어도 학부모 알림 기록은 생기지 않는다', (tester) async {
    // 등원 스캔으로 생긴 알림 한 건을 미리 심어 둔다. 0건에서 0건으로 끝나는 테스트는
    // getRecent 가 항상 빈 값을 줘도 통과하므로 아무것도 막지 못한다. 심어 둔 1건이
    // 그대로 1건이어야 "보정이 알림을 더하지 않았다"가 증명된다.
    final h = await pumpScreen(tester, (h) async {
      final id = await addMember(h, '김알림');
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: '2020-01-10',
          checkInTime: DateTime(2020, 1, 10, 9, 0).toIso8601String(),
          checkOutTime: DateTime(2020, 1, 10, 18, 0).toIso8601String(),
          status: AttendanceStatus.present,
        ),
      );
      await h.notifications.insert(
        NotificationLog(
          memberId: id,
          occurredAt: DateTime(2020, 1, 10, 9, 0).toIso8601String(),
          kind: NotificationKind.checkIn,
          recipient: '010-1111-2222',
        ),
      );
      return id;
    });
    await selectMember(tester, '김알림');
    final before = (await tester.runAsync(() => h.notifications.getRecent()))!;
    expect(before, hasLength(1), reason: '심어 둔 알림이 조회되지 않으면 이 테스트는 무의미하다');
    expect(before.single.kind, NotificationKind.checkIn);

    await openEdit(tester, '2020-01-10');
    await tester.tap(find.byKey(const Key('statusField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지각').last);
    await tester.pumpAndSettle();
    await save(tester, inRow(find.text('지각')));

    final saved = await savedRow(tester, h, '2020-01-10');
    expect(saved.status, AttendanceStatus.late);

    // 보정은 학부모 알림을 내지 않는다 (스펙 81~83행). 관리자가 다음 날 아침에 어제 기록을
    // 고쳤다고 학부모에게 "자녀가 나갔습니다"가 가면 이번 개정이 막으려 한 피해가 된다.
    final after = (await tester.runAsync(() => h.notifications.getRecent()))!;
    expect(after, hasLength(1));
    expect(after.single.occurredAt, before.single.occurredAt);
    expect(after.single.kind, NotificationKind.checkIn);
  });

  testWidgets('하원 시각을 보정해도 학부모 알림 기록은 생기지 않는다', (tester) async {
    // 상태 변경보다 이쪽이 위험하다 — 하원 시각을 채우는 보정은 학생이 하원 QR 을 찍은 것과
    // 결과가 같아 보이므로, 알림 경로에 얽히면 바로 거짓 알림이 나간다.
    final h = await pumpScreen(tester, (h) async {
      final id = await addMember(h, '김하원');
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: '2020-01-10',
          checkInTime: DateTime(2020, 1, 10, 9, 0).toIso8601String(),
          status: AttendanceStatus.present,
        ),
      );
      await h.notifications.insert(
        NotificationLog(
          memberId: id,
          occurredAt: DateTime(2020, 1, 10, 9, 0).toIso8601String(),
          kind: NotificationKind.checkIn,
          recipient: '010-1111-2222',
        ),
      );
      return id;
    });
    await selectMember(tester, '김하원');
    expect(
      (await tester.runAsync(() => h.notifications.getRecent()))!,
      hasLength(1),
    );

    await openEdit(tester, '2020-01-10');
    expect(inRow(find.text('등원 09:00 · 하원 없음')), findsOneWidget);
    await typeIn(tester, 'checkOutField', '18:00');
    await save(tester, inRow(find.text('등원 09:00 · 하원 18:00')));

    final saved = await savedRow(tester, h, '2020-01-10');
    expect(saved.checkOutTime, isNotNull);

    final after = (await tester.runAsync(() => h.notifications.getRecent()))!;
    expect(after, hasLength(1), reason: '하원 보정이 알림을 추가했다');
    expect(after.single.kind, NotificationKind.checkIn);
  });

  testWidgets('등원 후 12시간 이내의 열린 기록은 체류 중, 12시간이 지난 열린 기록은 미하원으로 구별한다', (
    tester,
  ) async {
    final now = DateTime.now();
    final recentIn = now.subtract(const Duration(hours: 1));
    final recentDate = dateKey(recentIn);
    await pumpScreen(tester, (h) async {
      final id = await addMember(h, '박체류');
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: recentDate,
          checkInTime: recentIn.toIso8601String(),
          status: AttendanceStatus.present,
        ),
      );
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: '2020-01-10',
          checkInTime: DateTime(2020, 1, 10, 9, 0).toIso8601String(),
          status: AttendanceStatus.present,
        ),
      );
      return id;
    });
    await selectMember(tester, '박체류');

    // 기본 달은 가장 최근 달(오늘 달)이다. 여기서는 체류 중 행만 보이고 미하원은 없다.
    expect(
      find.descendant(of: rowOf(recentDate), matching: find.text('체류 중')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rowOf(recentDate), matching: find.text('미하원')),
      findsNothing,
    );
    // 체류 중은 보정 대상이 아니므로 미하원 집계에 들어가지 않는다.
    expect(
      (tester.widget<Text>(summaryText)).data,
      '출석 1 · 지각 0 · 결석 0 · 미하원 0',
    );

    // 2020-01 행은 12시간이 지난 열린 기록이라 미하원이다.
    await selectMonth(tester, '2020-01');
    expect(
      find.descendant(of: rowOf('2020-01-10'), matching: find.text('미하원')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rowOf('2020-01-10'), matching: find.text('체류 중')),
      findsNothing,
    );
    expect(
      (tester.widget<Text>(summaryText)).data,
      '출석 1 · 지각 0 · 결석 0 · 미하원 1',
    );
  });

  testWidgets('월별 집계는 선택한 달의 기록만 세고, 달을 바꾸면 그 달로 다시 센다', (tester) async {
    await pumpScreen(tester, (h) async {
      final id = await addMember(h, '최월별');
      Future<void> add(
        String date,
        AttendanceStatus status, {
        DateTime? checkIn,
        DateTime? checkOut,
      }) => h.attendance.insert(
        Attendance(
          memberId: id,
          date: date,
          checkInTime: checkIn?.toIso8601String(),
          checkOutTime: checkOut?.toIso8601String(),
          status: status,
        ),
      );
      // 2020-08 : 출석 2, 미하원 1
      await add(
        '2020-08-05',
        AttendanceStatus.present,
        checkIn: DateTime(2020, 8, 5, 9, 0),
        checkOut: DateTime(2020, 8, 5, 18, 0),
      );
      await add(
        '2020-08-06',
        AttendanceStatus.present,
        checkIn: DateTime(2020, 8, 6, 9, 0),
      );
      // 2020-09 : 출석 1, 지각 1, 결석 1, 미하원 1
      await add(
        '2020-09-03',
        AttendanceStatus.late,
        checkIn: DateTime(2020, 9, 3, 10, 20),
        checkOut: DateTime(2020, 9, 3, 18, 0),
      );
      await add(
        '2020-09-10',
        AttendanceStatus.present,
        checkIn: DateTime(2020, 9, 10, 9, 0),
      );
      await add('2020-09-20', AttendanceStatus.absent);
      return id;
    });
    await selectMember(tester, '최월별');

    // 기본값은 가장 최근 달이다.
    expect(
      (tester.widget<Text>(summaryText)).data,
      '출석 1 · 지각 1 · 결석 1 · 미하원 1',
    );
    expect(rowOf('2020-09-03'), findsOneWidget);
    expect(rowOf('2020-08-05'), findsNothing);

    await selectMonth(tester, '2020-08');

    expect(
      (tester.widget<Text>(summaryText)).data,
      '출석 2 · 지각 0 · 결석 0 · 미하원 1',
    );
    expect(rowOf('2020-09-03'), findsNothing);
    expect(rowOf('2020-08-05'), findsOneWidget);
  });

  testWidgets('등원 시각 없이 하원 시각만 넣는 보정은 저장을 막는다', (tester) async {
    final h = await pumpScreen(tester, (h) async {
      final id = await addMember(h, '김결석');
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: '2020-01-10',
          status: AttendanceStatus.absent,
        ),
      );
      return id;
    });
    await selectMember(tester, '김결석');

    await openEdit(tester, '2020-01-10');
    await typeIn(tester, 'checkOutField', '18:00');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text(_orderError), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    final row = await savedRow(tester, h, '2020-01-10');
    expect(row.checkInTime, isNull);
    expect(row.checkOutTime, isNull);
  });

  testWidgets('HH:mm 형식이 아닌 시각은 저장을 막고 DB 를 바꾸지 않는다', (tester) async {
    final h = await pumpScreen(tester, (h) async {
      final id = await addMember(h, '김형식');
      await h.attendance.insert(
        Attendance(
          memberId: id,
          date: '2020-01-10',
          checkInTime: DateTime(2020, 1, 10, 9, 0).toIso8601String(),
          status: AttendanceStatus.present,
        ),
      );
      return id;
    });
    await selectMember(tester, '김형식');

    await openEdit(tester, '2020-01-10');
    await typeIn(tester, 'checkInField', '25:00');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text(_timeError), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    final row = await savedRow(tester, h, '2020-01-10');
    expect(row.checkInTime, DateTime(2020, 1, 10, 9, 0).toIso8601String());
  });
}
