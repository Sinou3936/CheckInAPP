import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/member.dart';

class MemberRepository {
  final Database db;
  MemberRepository(this.db);

  Future<int> insert(Member member) => db.insert('members', member.toMap());

  Future<void> update(Member member) => db.update(
    'members',
    member.toMap(),
    where: 'id = ?',
    whereArgs: [member.id],
  );

  Future<void> delete(int id) =>
      db.delete('members', where: 'id = ?', whereArgs: [id]);

  Future<Member?> getById(int id) async {
    final rows = await db.query('members', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Member.fromMap(rows.first);
  }

  Future<List<Member>> getAll() async {
    final rows = await db.query('members');
    return rows.map(Member.fromMap).toList();
  }

  Future<List<Member>> getByClassId(int classId) async {
    final rows = await db.query(
      'members',
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    return rows.map(Member.fromMap).toList();
  }
}
