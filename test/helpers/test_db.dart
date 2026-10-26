import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/db/database_helper.dart';

/// 데스크톱 SQLite 는 `sqflite` 가 아니라 `sqflite_common_ffi` 다. 전역 `openDatabase` 를
/// 쓰기 전에 이걸 불러야 한다.
///
/// DB 를 직접 열지 않고 **앱 코드가 열게 하는** 테스트(`main_smoke_test`)는 핸들이 필요 없고
/// 초기화만 필요하므로 이것만 부른다.
void initTestDatabaseFactory() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<Database> openTestDatabase() async {
  initTestDatabaseFactory();
  return DatabaseHelper.open(inMemoryDatabasePath);
}
