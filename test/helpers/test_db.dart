import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/db/database_helper.dart';

Future<Database> openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return DatabaseHelper.open(inMemoryDatabasePath);
}
