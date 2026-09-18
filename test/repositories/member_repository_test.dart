import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import '../helpers/test_db.dart';

void main() {
  test('insert, fetch, update, and delete a member', () async {
    final db = await openTestDatabase();
    final repo = MemberRepository(db);

    final id = await repo.insert(const Member(name: '홍길동', classId: null));
    final fetched = await repo.getById(id);
    expect(fetched?.name, '홍길동');

    await repo.update(fetched!.copyWith(name: '김철수'));
    final updated = await repo.getById(id);
    expect(updated?.name, '김철수');

    await repo.delete(id);
    expect(await repo.getById(id), isNull);
    await db.close();
  });

  test('getByClassId returns only members in that class', () async {
    final db = await openTestDatabase();
    final repo = MemberRepository(db);
    await repo.insert(const Member(name: 'A', classId: 1));
    await repo.insert(const Member(name: 'B', classId: 1));
    await repo.insert(const Member(name: 'C', classId: 2));

    final classOne = await repo.getByClassId(1);
    expect(classOne.map((m) => m.name).toSet(), {'A', 'B'});
    await db.close();
  });
}
