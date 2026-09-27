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

  Future<void> delete(int id) =>
      db.delete('classes', where: 'id = ?', whereArgs: [id]);

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
