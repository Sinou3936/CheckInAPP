import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static Future<Database> open(String path) async {
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            start_time TEXT NOT NULL,
            operating_days TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            class_id INTEGER,
            parent_contact TEXT,
            FOREIGN KEY (class_id) REFERENCES classes (id)
          )
        ''');
        await db.execute('''
          CREATE TABLE device_bindings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_token TEXT NOT NULL UNIQUE,
            member_id INTEGER NOT NULL,
            bound_at TEXT NOT NULL,
            FOREIGN KEY (member_id) REFERENCES members (id)
          )
        ''');
        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            member_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            check_in_time TEXT,
            check_out_time TEXT,
            status TEXT NOT NULL,
            UNIQUE(member_id, date),
            FOREIGN KEY (member_id) REFERENCES members (id)
          )
        ''');
        await db.execute('''
          CREATE TABLE notification_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            member_id INTEGER NOT NULL,
            occurred_at TEXT NOT NULL,
            kind TEXT NOT NULL,
            recipient TEXT,
            FOREIGN KEY (member_id) REFERENCES members (id)
          )
        ''');
        // device_token 에 UNIQUE 를 걸지 않는다 — 같은 기기가 여러 번 묶인 이력이
        // 모두 남아야 사칭 흔적이 보존된다.
        await db.execute('''
          CREATE TABLE binding_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_token TEXT NOT NULL,
            member_id INTEGER NOT NULL,
            occurred_at TEXT NOT NULL,
            FOREIGN KEY (member_id) REFERENCES members (id)
          )
        ''');
        // 앱 단위 상태. 현재 용도는 "자동 결석 처리를 마지막으로 완료한 날짜" 하나이며,
        // 이를 읽고 쓰는 저장소는 Task 18 에서 추가한다.
        await db.execute('''
          CREATE TABLE app_state (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }
}
