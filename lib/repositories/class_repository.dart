import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/class_model.dart';

class ClassRepository {
  final Database db;
  ClassRepository(this.db);

  Future<int> insert(ClassModel classModel) =>
      db.insert('classes', classModel.toMap());

  Future<void> update(ClassModel classModel) => db.update(
    'classes',
    classModel.toMap(),
    where: 'id = ?',
    whereArgs: [classModel.id],
  );

  /// 반을 지우면서 소속 회원의 반 지정을 null 로 비운다. 회원 자체는 지우지 않는다.
  /// `PRAGMA foreign_keys` 를 켜지 않으므로 정리를 여기서 직접 한다.
  Future<void> delete(int id) => db.transaction((txn) async {
    await txn.update(
      'members',
      {'class_id': null},
      where: 'class_id = ?',
      whereArgs: [id],
    );
    await txn.delete('classes', where: 'id = ?', whereArgs: [id]);
  });

  Future<ClassModel?> getById(int id) async {
    final rows = await db.query('classes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ClassModel.fromMap(rows.first);
  }

  Future<List<ClassModel>> getAll() async {
    final rows = await db.query('classes');
    return rows.map(ClassModel.fromMap).toList();
  }
}
