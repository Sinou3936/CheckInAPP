import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// testWidgets 의 fake-async zone 안에서는 sqflite_ffi 의 실제 비동기 호출이 pump 만으로
/// 끝나지 않는다. 실제 비동기를 조금씩 흘려보내고 프레임을 그리기를 번갈아 하면서,
/// [done] 이 참이 되면 즉시 빠져나온다. 고정 시간을 기다리지 않는다.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    // 0 초 pump 는 다이얼로그 닫힘 애니메이션을 진행시키지 못하므로 한 프레임만큼 시간을 흘린다.
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done(), isTrue, reason: '기다린 조건이 만족되지 않았다');
}

bool shown(Finder finder) => finder.evaluate().isNotEmpty;

bool absent(Finder finder) => finder.evaluate().isEmpty;

/// 목록 행 안에서만 찾는다. 열린 다이얼로그의 입력칸이나 안내문과 섞이지 않게 한다.
Finder inRow(Finder matching) =>
    find.descendant(of: find.byType(ListTile), matching: matching);
