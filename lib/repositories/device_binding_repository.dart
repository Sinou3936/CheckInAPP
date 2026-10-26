import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/binding_log.dart';
import 'package:checkin_app/models/device_binding.dart';

class DeviceBindingRepository {
  final Database db;
  DeviceBindingRepository(this.db);

  /// 기기 토큰을 회원에 묶는다.
  ///
  /// 현재 매핑은 토큰당 한 행이라 재바인딩 시 덮어써지지만, `binding_logs` 에는 매번
  /// 한 줄이 쌓인다 — 사칭이 있었다면 폰이 원래 주인에게 되돌려진 뒤에도 흔적이 남는다.
  Future<void> bind(String deviceToken, int memberId, {DateTime? now}) async {
    final boundAt = (now ?? DateTime.now()).toIso8601String();
    await db.insert(
      'device_bindings',
      DeviceBinding(
        deviceToken: deviceToken,
        memberId: memberId,
        boundAt: boundAt,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'binding_logs',
      BindingLog(
        deviceToken: deviceToken,
        memberId: memberId,
        occurredAt: boundAt,
      ).toMap(),
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

  /// 바인딩 이력을 최신순으로 돌려준다. 관리자가 사칭 여부를 점검하는 화면이 쓴다.
  Future<List<BindingLog>> getRecentLogs({int limit = 100}) async {
    final rows = await db.query(
      'binding_logs',
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(BindingLog.fromMap).toList();
  }
}
