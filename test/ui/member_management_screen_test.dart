import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/ui/screens/member_management_screen.dart';

import '../helpers/test_db.dart';

/// testWidgets 의 fake-async zone 안에서는 sqflite_ffi 의 실제 비동기 호출이 pump 만으로
/// 끝나지 않는다. 실제 비동기를 한 번 흘려보낸 뒤 프레임을 그린다.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pumpAndSettle();
}

class MemberHarness {
  final MemberRepository members;
  final ClassRepository classes;
  MemberHarness(this.members, this.classes);
}

Future<MemberHarness> pumpScreen(WidgetTester tester) async {
  final db = (await tester.runAsync(openTestDatabase))!;
  addTearDown(() => db.close());
  final harness = MemberHarness(MemberRepository(db), ClassRepository(db));
  await tester.pumpWidget(
    MaterialApp(
      home: MemberManagementScreen(
        memberRepository: harness.members,
        classRepository: harness.classes,
      ),
    ),
  );
  await settle(tester);
  return harness;
}

Future<void> openAddDialog(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.text('저장'));
  await settle(tester);
}

void main() {
  testWidgets('회원을 추가하면 목록에 나온다', (tester) async {
    await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await save(tester);

    expect(find.text('홍길동'), findsOneWidget);
  });

  testWidgets('학부모 연락처를 입력하면 저장되고 목록에 보인다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.enterText(
      find.byKey(const Key('memberContactField')),
      '010-1111-2222',
    );
    await save(tester);

    expect(find.textContaining('010-1111-2222'), findsOneWidget);
    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.parentContact, '010-1111-2222');
  });

  testWidgets('연락처가 없는 회원에는 관리자 대행 안내가 붙는다', (tester) async {
    await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await save(tester);

    expect(find.textContaining('관리자 대행'), findsOneWidget);
  });

  testWidgets('연락처가 있는 회원에는 관리자 대행 안내가 붙지 않는다', (tester) async {
    await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.enterText(
      find.byKey(const Key('memberContactField')),
      '010-1111-2222',
    );
    await save(tester);

    expect(find.textContaining('관리자 대행'), findsNothing);
  });

  testWidgets('연락처를 비워 저장하면 빈 문자열이 아니라 null 이 들어간다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await save(tester);

    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.parentContact, isNull);
  });

  testWidgets('공백만 입력한 연락처도 null 로 저장된다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.enterText(find.byKey(const Key('memberContactField')), '   ');
    await save(tester);

    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.parentContact, isNull);
  });

  testWidgets('수정에서 연락처를 지우면 null 로 돌아가고 안내가 다시 붙는다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.enterText(
      find.byKey(const Key('memberContactField')),
      '010-1111-2222',
    );
    await save(tester);

    await tester.tap(find.byTooltip('수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('memberContactField')), '');
    await save(tester);

    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.parentContact, isNull);
    expect(find.textContaining('관리자 대행'), findsOneWidget);
  });

  testWidgets('회원에 반을 지정할 수 있다', (tester) async {
    final h = await pumpScreen(tester);
    final classId = (await tester.runAsync(
      () => h.classes.insert(
        const ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1}),
      ),
    ))!;
    // 반은 화면이 뜰 때 읽으므로, 반을 만든 뒤 화면을 다시 띄운다.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: MemberManagementScreen(
          memberRepository: h.members,
          classRepository: h.classes,
        ),
      ),
    );
    await settle(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.tap(find.byKey(const Key('memberClassField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('국어반').last);
    await tester.pumpAndSettle();
    await save(tester);

    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.classId, classId);
    expect(find.textContaining('국어반'), findsOneWidget);
  });

  testWidgets('회원을 삭제하면 목록에서 사라진다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await save(tester);
    expect(find.text('홍길동'), findsOneWidget);

    await tester.tap(find.byTooltip('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').last);
    await settle(tester);

    expect(find.text('홍길동'), findsNothing);
    expect((await tester.runAsync(h.members.getAll))!, isEmpty);
  });
}
