import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/ui/screens/class_management_screen.dart';

import '../helpers/test_db.dart';
import '../helpers/widget_test_helpers.dart';

const _timeError = '시작 시간을 HH:mm 형식으로 입력하세요 (예: 15:00)';
const _nameError = '반 이름을 입력하세요';
const _daysError = '운영 요일을 하나 이상 고르세요';

class ClassHarness {
  final ClassRepository classes;
  final MemberRepository members;
  ClassHarness(this.classes, this.members);
}

Future<ClassHarness> pumpScreen(
  WidgetTester tester, {
  Future<void> Function(ClassHarness h)? seed,
}) async {
  final db = (await tester.runAsync(openTestDatabase))!;
  addTearDown(() => db.close());
  final harness = ClassHarness(ClassRepository(db), MemberRepository(db));
  if (seed != null) await tester.runAsync(() => seed(harness));
  await tester.pumpWidget(
    MaterialApp(home: ClassManagementScreen(classRepository: harness.classes)),
  );
  await pumpUntil(tester, () => absent(find.byType(CircularProgressIndicator)));
  return harness;
}

Future<void> openAddDialog(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

Future<void> openEditDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('수정'));
  await tester.pumpAndSettle();
}

/// 요일 칩을 한 번 누른다. 라벨은 월~일 한 글자다.
Future<void> toggleDay(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilterChip, label));
  await tester.pump();
}

/// 저장은 다이얼로그를 닫은 뒤에야 DB 쓰기와 목록 재조회를 시작한다. 그래서 다이얼로그가
/// 닫힌 것만으로는 끝난 것이 아니고, [listed] 가 보여야 재조회까지 끝난 것이다.
Future<void> save(WidgetTester tester, Finder listed) async {
  await tester.tap(find.widgetWithText(FilledButton, '저장'));
  await pumpUntil(
    tester,
    () => absent(find.byType(AlertDialog)) && shown(listed),
  );
  expect(find.byType(AlertDialog), findsNothing);
}

/// 입력칸의 현재 글자. 양식이 기존 값을 채워 열렸는지 확인할 때 쓴다.
String fieldText(WidgetTester tester, Key key) {
  final editable = tester.widget<EditableText>(
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
  );
  return editable.controller.text;
}

void main() {
  testWidgets('로드 전에는 로딩 표시만 보이고 빈 목록 안내는 보이지 않는다', (tester) async {
    final db = (await tester.runAsync(openTestDatabase))!;
    addTearDown(() => db.close());
    await tester.pumpWidget(
      MaterialApp(
        home: ClassManagementScreen(classRepository: ClassRepository(db)),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('등록된 반이 없습니다.'), findsNothing);

    await pumpUntil(
      tester,
      () => absent(find.byType(CircularProgressIndicator)),
    );
    expect(find.text('등록된 반이 없습니다.'), findsOneWidget);
  });

  testWidgets('반을 추가하면 목록에 나오고 이름·시작 시간·요일이 저장된다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('classNameField')), '국어반');
    await tester.enterText(find.byKey(const Key('classTimeField')), '15:00');
    await toggleDay(tester, '월');
    await save(tester, inRow(find.text('국어반')));

    expect(inRow(find.text('국어반')), findsOneWidget);
    expect(inRow(find.text('시작 시간: 15:00')), findsOneWidget);
    final saved = (await tester.runAsync(h.classes.getAll))!;
    expect(saved.single.name, '국어반');
    expect(saved.single.startTime, '15:00');
    expect(saved.single.operatingDays, {1});
  });

  testWidgets('요일 칩은 월~일로 보이고, 고른 요일만 정렬된 라벨로 나온다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    for (final label in ['월', '화', '수', '목', '금', '토', '일']) {
      expect(find.widgetWithText(FilterChip, label), findsOneWidget);
    }
    await tester.enterText(find.byKey(const Key('classNameField')), '국어반');
    await tester.enterText(find.byKey(const Key('classTimeField')), '15:00');
    // 누른 순서와 무관하게 저장과 표시는 요일 순서(월→일)를 따른다.
    await toggleDay(tester, '금');
    await toggleDay(tester, '월');
    await toggleDay(tester, '수');
    await save(tester, inRow(find.text('국어반')));

    expect(inRow(find.text('운영 요일: 월·수·금')), findsOneWidget);
    final saved = (await tester.runAsync(h.classes.getAll))!;
    expect(saved.single.operatingDays, {1, 3, 5});
  });

  testWidgets('이름이 비어 있으면 저장되지 않고 다이얼로그가 남는다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('classNameField')), '   ');
    await tester.enterText(find.byKey(const Key('classTimeField')), '15:00');
    await toggleDay(tester, '월');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text(_nameError), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect((await tester.runAsync(h.classes.getAll))!, isEmpty);
  });

  testWidgets('HH:mm 이 아닌 시작 시간은 저장되지 않는다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('classNameField')), '국어반');
    await toggleDay(tester, '월');

    for (final bad in [
      '',
      '15시',
      '3:00 PM',
      '24:00',
      '15:60',
      '9:00',
      '15:0',
    ]) {
      await tester.enterText(find.byKey(const Key('classTimeField')), bad);
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();

      expect(
        find.text(_timeError),
        findsOneWidget,
        reason: '"$bad" 가 거부되지 않았다',
      );
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: '"$bad" 에서 다이얼로그가 닫혔다',
      );
    }
    expect((await tester.runAsync(h.classes.getAll))!, isEmpty);
  });

  testWidgets('경계 시각 23:59 는 통과한다', (tester) async {
    await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('classNameField')), '야간반');
    await tester.enterText(find.byKey(const Key('classTimeField')), '23:59');
    await toggleDay(tester, '월');
    await save(tester, inRow(find.text('야간반')));

    expect(inRow(find.text('시작 시간: 23:59')), findsOneWidget);
  });

  testWidgets('운영 요일을 하나도 고르지 않으면 저장되지 않고, 요일을 고르면 오류가 사라진다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('classNameField')), '국어반');
    await tester.enterText(find.byKey(const Key('classTimeField')), '15:00');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text(_daysError), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect((await tester.runAsync(h.classes.getAll))!, isEmpty);

    await toggleDay(tester, '화');
    expect(find.text(_daysError), findsNothing);
  });

  testWidgets('수정하면 이름·시작 시간·요일이 바뀌고 같은 반으로 남는다', (tester) async {
    late int classId;
    final h = await pumpScreen(
      tester,
      seed: (h) async {
        classId = await h.classes.insert(
          const ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1}),
        );
      },
    );

    await openEditDialog(tester);
    expect(fieldText(tester, const Key('classNameField')), '국어반');
    expect(fieldText(tester, const Key('classTimeField')), '15:00');
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '월')).selected,
      isTrue,
    );

    await tester.enterText(find.byKey(const Key('classNameField')), '수학반');
    await tester.enterText(find.byKey(const Key('classTimeField')), '16:00');
    await toggleDay(tester, '월');
    await toggleDay(tester, '수');
    await save(tester, inRow(find.text('수학반')));

    expect(inRow(find.text('시작 시간: 16:00')), findsOneWidget);
    expect(inRow(find.text('운영 요일: 수')), findsOneWidget);
    final saved = (await tester.runAsync(h.classes.getAll))!;
    expect(saved, hasLength(1));
    expect(saved.single.id, classId);
    expect(saved.single.name, '수학반');
    expect(saved.single.startTime, '16:00');
    expect(saved.single.operatingDays, {3});
  });

  testWidgets('반을 수정해도 소속 회원의 반 지정은 그대로다', (tester) async {
    late int classId;
    final h = await pumpScreen(
      tester,
      seed: (h) async {
        classId = await h.classes.insert(
          const ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1}),
        );
        await h.members.insert(Member(name: '홍길동', classId: classId));
      },
    );

    await openEditDialog(tester);
    await tester.enterText(find.byKey(const Key('classNameField')), '수학반');
    await save(tester, inRow(find.text('수학반')));

    final members = (await tester.runAsync(h.members.getAll))!;
    expect(members.single.classId, classId);
  });

  testWidgets('삭제 확인 문구에 소속 회원의 반 지정이 해제된다는 내용이 있다', (tester) async {
    await pumpScreen(
      tester,
      seed: (h) async {
        await h.classes.insert(
          const ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1}),
        );
      },
    );

    await tester.tap(find.byTooltip('삭제'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('반 지정만 해제'), findsOneWidget);
  });

  testWidgets('삭제를 확인하면 반이 목록에서 사라지고 소속 회원은 남는다', (tester) async {
    final h = await pumpScreen(
      tester,
      seed: (h) async {
        final classId = await h.classes.insert(
          const ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1}),
        );
        await h.members.insert(Member(name: '홍길동', classId: classId));
      },
    );

    await tester.tap(find.byTooltip('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await pumpUntil(
      tester,
      () => absent(find.byType(AlertDialog)) && absent(inRow(find.text('국어반'))),
    );

    expect(inRow(find.text('국어반')), findsNothing);
    expect((await tester.runAsync(h.classes.getAll))!, isEmpty);
    final members = (await tester.runAsync(h.members.getAll))!;
    expect(members.single.name, '홍길동');
    expect(members.single.classId, isNull);
  });

  testWidgets('삭제 확인에서 취소하면 반이 남는다', (tester) async {
    final h = await pumpScreen(
      tester,
      seed: (h) async {
        await h.classes.insert(
          const ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1}),
        );
      },
    );

    await tester.tap(find.byTooltip('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await pumpUntil(tester, () => absent(find.byType(AlertDialog)));

    expect(inRow(find.text('국어반')), findsOneWidget);
    expect((await tester.runAsync(h.classes.getAll))!, hasLength(1));
  });
}
