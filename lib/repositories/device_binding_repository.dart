import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/device_binding.dart';

class DeviceBindingRepository {
  final Database db;
  DeviceBindingRepository(this.db);

  Future<void> bind(String deviceToken, int memberId) async {
    await db.insert(
      'device_bindings',
      {'device_token': deviceToken, 'member_id': memberId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DeviceBinding?> getByToken(String deviceToken) async {
    final rows = await db.query(
      'device_bindings',
      where: 'device_token = ?',
      whereArgs: [deviceToken],
    );
    if (rows.isEmpty) return null;
    return DeviceBinding.fromMap(rows.first);
  }
}
