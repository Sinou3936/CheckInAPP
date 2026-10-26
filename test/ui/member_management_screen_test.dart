import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/admin_bind_code_service.dart';
import 'package:checkin_app/ui/screens/member_management_screen.dart';

import '../helpers/test_db.dart';
import '../helpers/widget_test_helpers.dart';

class MemberHarness {
  final MemberRepository members;
  final ClassRepository classes;
  MemberHarness(this.members, this.classes);
}

Future<MemberHarness> pumpScreen(
  WidgetTester tester, {
  Future<void> Function(MemberHarness h)? seed,
  AdminBindCodeService? bindCodes,
}) async {
  final db = (await tester.runAsync(openTestDatabase))!;
  addTearDown(() => db.close());
  final harness = MemberHarness(MemberRepository(db), ClassRepository(db));
  if (seed != null) await tester.runAsync(() => seed(harness));
  await tester.pumpWidget(
    MaterialApp(
      home: MemberManagementScreen(
        memberRepository: harness.members,
        classRepository: harness.classes,
        adminBindCodeService: bindCodes,
      ),
    ),
  );
  await pumpUntil(tester, () => absent(find.byType(CircularProgressIndicator)));
  return harness;
}

Future<void> openAddDialog(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

/// 저장은 다이얼로그를 닫은 뒤에야 DB 쓰기와 목록 재조회를 시작한다. 그래서 다이얼로그가
/// 닫힌 것만으로는 끝난 것이 아니고, [listed] 가 보여야 재조회까지 끝난 것이다.
Future<void> save(WidgetTester tester, Finder listed) async {
  await tester.tap(find.text('저장'));
  await pumpUntil(
    tester,
    () => absent(find.byType(AlertDialog)) && shown(listed),
  );
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  testWidgets('로드 전에는 로딩 표시만 보이고 빈 목록 안내는 보이지 않는다', (tester) async {
    final db = (await tester.runAsync(openTestDatabase))!;
    addTearDown(() => db.close());
    await tester.pumpWidget(
      MaterialApp(
        home: MemberManagementScreen(
          memberRepository: MemberRepository(db),
          classRepository: ClassRepository(db),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('등록된 회원이 없습니다.'), findsNothing);

    await pumpUntil(
      tester,
      () => absent(find.byType(CircularProgressIndicator)),
    );
    expect(find.text('등록된 회원이 없습니다.'), findsOneWidget);
  });

  testWidgets('회원을 추가하면 목록에 나온다', (tester) async {
    await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await save(tester, inRow(find.text('홍길동')));

    expect(inRow(find.text('홍길동')), findsOneWidget);
  });

  testWidgets('학부모 연락처를 입력하면 저장되고 목록에 보인다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.enterText(
      find.byKey(const Key('memberContactField')),
      '010-1111-2222',
    );
    await save(tester, inRow(find.textContaining('010-1111-2222')));

    expect(inRow(find.textContaining('010-1111-2222')), findsOneWidget);
    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.parentContact, '010-1111-2222');
  });

  testWidgets('연락처가 없는 회원에는 관리자 대행 안내가 붙는다', (tester) async {
    await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await save(tester, inRow(find.textContaining('관리자 대행')));

    expect(inRow(find.textContaining('관리자 대행')), findsOneWidget);
  });

  testWidgets('연락처가 있는 회원에는 관리자 대행 안내가 붙지 않는다', (tester) async {
    await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.enterText(
      find.byKey(const Key('memberContactField')),
      '010-1111-2222',
    );
    await save(tester, inRow(find.text('홍길동')));

    expect(inRow(find.textContaining('관리자 대행')), findsNothing);
  });

  testWidgets('숫자가 4자리 미만인 연락처는 연락처를 보여주면서 대행 안내도 붙는다', (tester) async {
    await pumpScreen(
      tester,
      seed: (h) async {
        await h.members.insert(const Member(name: '홍길동', parentContact: '미정'));
      },
    );

    expect(inRow(find.textContaining('학부모 연락처: 미정')), findsOneWidget);
    expect(inRow(find.textContaining('관리자 대행')), findsOneWidget);
  });

  testWidgets('연락처를 비워 저장하면 빈 문자열이 아니라 null 이 들어간다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await save(tester, inRow(find.textContaining('관리자 대행')));

    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.parentContact, isNull);
  });

  testWidgets('공백만 입력한 연락처도 null 로 저장된다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.enterText(find.byKey(const Key('memberContactField')), '   ');
    await save(tester, inRow(find.textContaining('관리자 대행')));

    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.parentContact, isNull);
  });

  testWidgets('이름이 비어 있으면 저장되지 않고 다이얼로그가 남는다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '   ');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('이름을 입력하세요'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect((await tester.runAsync(h.members.getAll))!, isEmpty);
  });

  testWidgets('수정에서 연락처를 지우면 null 로 돌아가고 안내가 다시 붙는다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.enterText(
      find.byKey(const Key('memberContactField')),
      '010-1111-2222',
    );
    await save(tester, inRow(find.textContaining('010-1111-2222')));

    await tester.tap(find.byTooltip('수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('memberContactField')), '');
    await save(tester, inRow(find.textContaining('관리자 대행')));

    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.parentContact, isNull);
    expect(inRow(find.textContaining('관리자 대행')), findsOneWidget);
  });

  testWidgets('회원에 반을 지정할 수 있다', (tester) async {
    late int classId;
    final h = await pumpScreen(
      tester,
      seed: (h) async {
        classId = await h.classes.insert(
          const ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1}),
        );
      },
    );

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await tester.tap(find.byKey(const Key('memberClassField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('국어반').last);
    await tester.pumpAndSettle();
    await save(tester, inRow(find.textContaining('국어반')));

    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.classId, classId);
  });

  testWidgets('반이 삭제된 회원의 수정 다이얼로그도 예외 없이 열린다', (tester) async {
    await pumpScreen(
      tester,
      seed: (h) async {
        await h.members.insert(const Member(name: '홍길동', classId: 999));
      },
    );

    await tester.tap(find.byTooltip('수정'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('memberClassField')),
        matching: find.text('반 없음'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('반이 사라진 회원을 저장하면 classId 가 null 로 정규화된다', (tester) async {
    final h = await pumpScreen(
      tester,
      seed: (h) async {
        await h.members.insert(const Member(name: '홍길동', classId: 999));
      },
    );

    await tester.tap(find.byTooltip('수정'));
    await tester.pumpAndSettle();
    await save(tester, inRow(find.textContaining('반: 반 없음')));

    final saved = (await tester.runAsync(h.members.getAll))!;
    expect(saved.single.classId, isNull);
  });

  testWidgets('회원을 삭제하면 목록에서 사라진다', (tester) async {
    final h = await pumpScreen(tester);

    await openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('memberNameField')), '홍길동');
    await save(tester, inRow(find.text('홍길동')));
    expect(inRow(find.text('홍길동')), findsOneWidget);

    await tester.tap(find.byTooltip('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').last);
    await pumpUntil(
      tester,
      () => absent(find.byType(AlertDialog)) && absent(inRow(find.text('홍길동'))),
    );

    expect(inRow(find.text('홍길동')), findsNothing);
    expect((await tester.runAsync(h.members.getAll))!, isEmpty);
  });

  testWidgets('삭제 확인에서 취소하면 회원이 남는다', (tester) async {
    final h = await pumpScreen(
      tester,
      seed: (h) async {
        await h.members.insert(const Member(name: '홍길동'));
      },
    );

    await tester.tap(find.byTooltip('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await pumpUntil(tester, () => absent(find.byType(AlertDialog)));

    expect(inRow(find.text('홍길동')), findsOneWidget);
    expect((await tester.runAsync(h.members.getAll))!, hasLength(1));
  });

  testWidgets('연락처 없는 회원에게만 연동 코드 발급 버튼이 보이고 코드가 서버 발급기와 일치한다', (tester) async {
    final bindCodes = AdminBindCodeService();
    late int noContactId;
    await pumpScreen(
      tester,
      bindCodes: bindCodes,
      seed: (h) async {
        noContactId = await h.members.insert(const Member(name: '연락처없음'));
        await h.members.insert(
          const Member(name: '연락처있음', parentContact: '010-1111-2222'),
        );
      },
    );

    // 대행이 필요한 회원 한 명에게만 버튼이 있다.
    expect(find.byTooltip('기기 연동 코드 발급'), findsOneWidget);

    await tester.tap(find.byTooltip('기기 연동 코드 발급'));
    await tester.pumpAndSettle();
    final code = tester
        .widget<SelectableText>(find.byKey(const Key('bindCodeText')))
        .data!;
    expect(code, matches(RegExp(r'^[0-9]{6}$')));
    expect(bindCodes.consume(noContactId, code), isTrue);
  });

  testWidgets('발급기를 넘기지 않으면 발급 버튼이 없다', (tester) async {
    await pumpScreen(
      tester,
      seed: (h) async {
        await h.members.insert(const Member(name: '연락처없음'));
      },
    );
    expect(find.byTooltip('기기 연동 코드 발급'), findsNothing);
  });
}
