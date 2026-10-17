import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';

import '../helpers/test_db.dart';

void main() {
  test('반을 지우면 소속 회원은 남고 반 지정만 null 이 된다', () async {
    final db = await openTestDatabase();
    final classRepo = ClassRepository(db);
    final memberRepo = MemberRepository(db);

    final classId = await classRepo.insert(
      ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1}),
    );
    final otherClassId = await classRepo.insert(
      ClassModel(name: '수학반', startTime: '16:00', operatingDays: {2}),
    );
    final memberId = await memberRepo.insert(
      Member(name: '홍길동', classId: classId),
    );
    await memberRepo.insert(Member(name: '김철수', classId: otherClassId));

    await classRepo.delete(classId);

    expect(await classRepo.getById(classId), isNull);
    final member = await memberRepo.getById(memberId);
    expect(member, isNotNull, reason: '회원은 지워지지 않아야 한다');
    expect(member!.classId, isNull);
    final other = await memberRepo.getAll();
    expect(
      other.firstWhere((m) => m.name == '김철수').classId,
      otherClassId,
      reason: '다른 반 소속 회원은 그대로여야 한다',
    );
    await db.close();
  });

  test('insert, fetch, update, and delete a class', () async {
    final db = await openTestDatabase();
    final repo = ClassRepository(db);

    final id = await repo.insert(
      ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1, 3, 5}),
    );
    final fetched = await repo.getById(id);
    expect(fetched?.name, '국어반');
    expect(fetched?.operatingDays, {1, 3, 5});

    await repo.update(
      ClassModel(
        id: id,
        name: '수학반',
        startTime: '16:00',
        operatingDays: {2, 4},
      ),
    );
    final updated = await repo.getById(id);
    expect(updated?.name, '수학반');
    expect(updated?.startTime, '16:00');

    await repo.delete(id);
    expect(await repo.getById(id), isNull);
    await db.close();
  });

  test('getAll returns every class', () async {
    final db = await openTestDatabase();
    final repo = ClassRepository(db);
    await repo.insert(
      ClassModel(name: 'A', startTime: '09:00', operatingDays: {1}),
    );
    await repo.insert(
      ClassModel(name: 'B', startTime: '10:00', operatingDays: {2}),
    );

    final all = await repo.getAll();
    expect(all.map((c) => c.name).toSet(), {'A', 'B'});
    await db.close();
  });
}
