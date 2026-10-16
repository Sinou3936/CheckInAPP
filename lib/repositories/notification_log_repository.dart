import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/notification_log.dart';

class NotificationLogRepository {
  final Database db;
  NotificationLogRepository(this.db);

  Future<int> insert(NotificationLog log) =>
      db.insert('notification_logs', log.toMap());

  /// 발생 시각 최신순. 관리자 화면의 "알림 내역"이 이 결과를 보여준다.
  Future<List<NotificationLog>> getRecent({int limit = 50}) async {
    final rows = await db.query(
      'notification_logs',
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(NotificationLog.fromMap).toList();
  }
}
