import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_db.dart';

void main() {
  test('opens an in-memory database with every table', () async {
    final db = await openTestDatabase();
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll([
        'classes',
        'members',
        'device_bindings',
        'attendance',
        'notification_logs',
        'binding_logs',
        'app_state',
      ]),
    );
    await db.close();
  });

  test('체크아웃·알림·바인딩 이력에 필요한 컬럼이 있다', () async {
    final db = await openTestDatabase();
    Future<Set<Object?>> cols(String table) async =>
        (await db.rawQuery('PRAGMA table_info($table)'))
            .map((r) => r['name'])
            .toSet();

    expect(await cols('attendance'), contains('check_out_time'));
    expect(await cols('members'), contains('parent_contact'));
    expect(await cols('device_bindings'), contains('bound_at'));
    await db.close();
  });
}
