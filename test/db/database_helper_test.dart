import 'package:flutter_test/flutter_test.dart';
import '../helpers/test_db.dart';

void main() {
  test('opens an in-memory database with all four tables', () async {
    final db = await openTestDatabase();
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(names, containsAll(['classes', 'members', 'device_bindings', 'attendance']));
    await db.close();
  });
}
