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
}
