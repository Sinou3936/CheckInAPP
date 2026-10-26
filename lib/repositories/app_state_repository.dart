import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 앱 단위 키-값 상태. 현재 용도는 자동 결석 처리를 마지막으로 완료한 날짜 하나다.
class AppStateRepository {
  final Database db;
  AppStateRepository(this.db);

  Future<String?> get(String key) async {
    final rows = await db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> set(String key, String value) => db.insert('app_state', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
