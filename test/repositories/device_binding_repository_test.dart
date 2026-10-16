import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';

import '../helpers/test_db.dart';

void main() {
  test('bind creates a new binding, and getByToken returns it', () async {
    final db = await openTestDatabase();
    final repo = DeviceBindingRepository(db);

    await repo.bind('device-1', 42);
    final binding = await repo.getByToken('device-1');
    expect(binding?.memberId, 42);
    await db.close();
  });

  test('bind on an existing token rebinds it to the new member', () async {
    final db = await openTestDatabase();
    final repo = DeviceBindingRepository(db);

    await repo.bind('device-1', 42);
    await repo.bind('device-1', 99);
    final binding = await repo.getByToken('device-1');
    expect(binding?.memberId, 99);
    await db.close();
  });

  test('unknown token returns null', () async {
    final db = await openTestDatabase();
    final repo = DeviceBindingRepository(db);
    expect(await repo.getByToken('nope'), isNull);
    await db.close();
  });

  test('bind 는 바인딩 시각을 기록한다', () async {
    final db = await openTestDatabase();
    final repo = DeviceBindingRepository(db);

    await repo.bind('device-1', 42, now: DateTime(2026, 10, 16, 15, 0));
    final binding = await repo.getByToken('device-1');
    expect(binding!.boundAt, DateTime(2026, 10, 16, 15, 0).toIso8601String());
    await db.close();
  });

  test('재바인딩해도 이전 바인딩 이력이 남는다', () async {
    final db = await openTestDatabase();
    final repo = DeviceBindingRepository(db);

    await repo.bind('device-1', 42, now: DateTime(2026, 10, 16, 15, 0));
    await repo.bind('device-1', 99, now: DateTime(2026, 10, 16, 16, 0));

    expect((await repo.getByToken('device-1'))!.memberId, 99);
    final logs = await db.query('binding_logs', orderBy: 'occurred_at');
    expect(logs.map((r) => r['member_id']).toList(), [42, 99]);
    await db.close();
  });
}
