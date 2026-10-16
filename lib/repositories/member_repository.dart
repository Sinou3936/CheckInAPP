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

  /// 회원과 그 회원의 기기 바인딩을 함께 지운다. `PRAGMA foreign_keys` 를 켜지 않으므로
  /// 정리를 여기서 직접 한다. `binding_logs` 는 사칭 점검용 append-only 기록이라 남긴다.
  Future<void> delete(int id) => db.transaction((txn) async {
    await txn.delete(
      'device_bindings',
      where: 'member_id = ?',
      whereArgs: [id],
    );
    await txn.delete('members', where: 'id = ?', whereArgs: [id]);
  });

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
