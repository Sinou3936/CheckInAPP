import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import '../helpers/test_db.dart';

void main() {
  test('insert, fetch, update, and delete a class', () async {
    final db = await openTestDatabase();
    final repo = ClassRepository(db);

    final id = await repo.insert(ClassModel(
      name: '국어반',
      startTime: '15:00',
      operatingDays: {1, 3, 5},
    ));
    final fetched = await repo.getById(id);
    expect(fetched?.name, '국어반');
    expect(fetched?.operatingDays, {1, 3, 5});

    await repo.update(ClassModel(
      id: id,
      name: '수학반',
      startTime: '16:00',
      operatingDays: {2, 4},
    ));
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
    await repo.insert(ClassModel(name: 'A', startTime: '09:00', operatingDays: {1}));
    await repo.insert(ClassModel(name: 'B', startTime: '10:00', operatingDays: {2}));

    final all = await repo.getAll();
    expect(all.map((c) => c.name).toSet(), {'A', 'B'});
    await db.close();
  });
}
