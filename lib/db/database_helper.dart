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
            FOREIGN KEY (class_id) REFERENCES classes (id)
          )
        ''');
        await db.execute('''
          CREATE TABLE device_bindings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_token TEXT NOT NULL UNIQUE,
            member_id INTEGER NOT NULL,
            FOREIGN KEY (member_id) REFERENCES members (id)
          )
        ''');
        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            member_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            check_in_time TEXT,
            status TEXT NOT NULL,
            UNIQUE(member_id, date),
            FOREIGN KEY (member_id) REFERENCES members (id)
          )
        ''');
      },
    );
  }
}
