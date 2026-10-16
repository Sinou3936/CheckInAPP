import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
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

  test('회원을 지우면 그 기기 바인딩도 지워진다', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final repo = MemberRepository(db);
    final deviceRepo = DeviceBindingRepository(db);

    final id = await repo.insert(const Member(name: '홍길동'));
    await deviceRepo.bind('device-1', id);
    expect(await deviceRepo.getByToken('device-1'), isNotNull);

    await repo.delete(id);

    expect(await deviceRepo.getByToken('device-1'), isNull);
    // 사칭 점검용 append-only 기록은 회원을 지워도 남는다.
    final logs = await db.query('binding_logs');
    expect(logs, hasLength(1));
    expect(logs.single['member_id'], id);
  });

  test('다른 회원의 바인딩은 지우지 않는다', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final repo = MemberRepository(db);
    final deviceRepo = DeviceBindingRepository(db);

    final a = await repo.insert(const Member(name: 'A'));
    final b = await repo.insert(const Member(name: 'B'));
    await deviceRepo.bind('device-a', a);
    await deviceRepo.bind('device-b', b);

    await repo.delete(a);

    expect(await deviceRepo.getByToken('device-a'), isNull);
    expect(await deviceRepo.getByToken('device-b'), isNotNull);
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
