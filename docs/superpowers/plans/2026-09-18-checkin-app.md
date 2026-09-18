# CheckInApp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter Desktop (Windows) attendance-management app where an admin manages members/classes on a counter PC, and members self-check-in from their own phone by scanning a rotating QR code shown on that PC, over the local network only.

**Architecture:** A single Flutter desktop app owns a local SQLite database and runs an embedded HTTP server (shelf) in-process. The admin UI reads/writes the database directly through repository classes. The embedded server exposes a tiny JSON API plus a static check-in web page that a member's phone opens after scanning the QR code; the page talks only to that local server, never to the internet.

**Tech Stack:** Flutter Desktop (Windows), Dart, `sqflite_common_ffi` (SQLite), `shelf` + `shelf_router` (embedded HTTP server), `qr_flutter` (QR rendering), `path_provider` (app data directory).

**Spec:** `<repo root>\2026-09-18-checkin-app-design.md`

## Global Constraints

- No cloud/external hosting — the check-in server only ever binds to the local network (spec: "AWS 무료 티어 종료로 배제").
- Late-arrival grace period: 10 minutes after a class's start time (spec example value).
- QR token rotation interval: 30 seconds, with a 10-second overlap grace window for tokens that just rotated (spec example value).
- One member belongs to at most one class — multi-class membership is explicitly out of scope.
- No real phone numbers are ever stored — only an anonymous per-device token (spec: "실제 연락처 정보 저장용으로 쓰는건 아니지").
- No admin login for the desktop app (counter-PC assumption from spec).
- All commands in this plan assume the working directory is `<repo root>` (a subdirectory of the existing WorkFolder git repo — `git` commands work fine run from here).

---

## Task 1: Project scaffold + data models

**Files:**
- Create: `pubspec.yaml` (via `flutter create`, then edited)
- Create: `lib/models/member.dart`
- Create: `lib/models/class_model.dart`
- Create: `lib/models/attendance.dart`
- Create: `lib/models/device_binding.dart`
- Test: `test/models/models_test.dart`

**Interfaces:**
- Produces: `Member(id, name, classId)`, `ClassModel(id, name, startTime, operatingDays)` with `operatesOn(DateTime)` and `startDateTimeFor(DateTime)`, `AttendanceStatus{present,late,absent}`, `Attendance(id, memberId, date, checkInTime, status)`, `DeviceBinding(id, deviceToken, memberId)`. Each model has `toMap()` / `fromMap(Map<String,Object?>)`.

- [ ] **Step 1: Scaffold the Flutter project**

Run (folder name `CheckInApp` is not a valid Dart package name, so the project name is passed explicitly):

```bash
flutter create --project-name checkin_app --platforms=windows .
flutter config --enable-windows-desktop
```

- [ ] **Step 2: Add dependencies**

Edit `pubspec.yaml`, adding under `dependencies:`:

```yaml
  sqflite_common_ffi: ^2.3.0
  shelf: ^1.4.0
  shelf_router: ^1.1.4
  qr_flutter: ^4.1.0
  path_provider: ^2.1.0
  path: ^1.9.0
```

and under `dev_dependencies:`:

```yaml
  http: ^1.2.0
```

Run: `flutter pub get`
Expected: resolves with no errors.

- [ ] **Step 3: Write the failing test**

Create `test/models/models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/device_binding.dart';

void main() {
  test('Member round-trips through toMap/fromMap', () {
    const member = Member(id: 1, name: '홍길동', classId: 2);
    final restored = Member.fromMap(member.toMap());
    expect(restored.id, 1);
    expect(restored.name, '홍길동');
    expect(restored.classId, 2);
  });

  test('ClassModel round-trips and reports operating days correctly', () {
    final classModel = ClassModel(
      id: 1,
      name: '국어반',
      startTime: '15:00',
      operatingDays: {1, 3, 5}, // Mon/Wed/Fri
    );
    final restored = ClassModel.fromMap(classModel.toMap());
    expect(restored.name, '국어반');
    expect(restored.startTime, '15:00');
    expect(restored.operatingDays, {1, 3, 5});
    expect(restored.operatesOn(DateTime(2026, 9, 21)), isTrue); // Monday
    expect(restored.operatesOn(DateTime(2026, 9, 22)), isFalse); // Tuesday
    final start = restored.startDateTimeFor(DateTime(2026, 9, 21));
    expect(start, DateTime(2026, 9, 21, 15, 0));
  });

  test('Attendance round-trips including null checkInTime', () {
    const attendance = Attendance(
      id: 1,
      memberId: 5,
      date: '2026-09-18',
      checkInTime: null,
      status: AttendanceStatus.absent,
    );
    final restored = Attendance.fromMap(attendance.toMap());
    expect(restored.memberId, 5);
    expect(restored.checkInTime, isNull);
    expect(restored.status, AttendanceStatus.absent);
  });

  test('DeviceBinding round-trips', () {
    const binding = DeviceBinding(id: 1, deviceToken: 'abc123', memberId: 7);
    final restored = DeviceBinding.fromMap(binding.toMap());
    expect(restored.deviceToken, 'abc123');
    expect(restored.memberId, 7);
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/models/models_test.dart`
Expected: FAIL — the `lib/models/*.dart` files don't exist yet (import errors).

- [ ] **Step 5: Implement the models**

Create `lib/models/member.dart`:

```dart
class Member {
  final int? id;
  final String name;
  final int? classId;

  const Member({this.id, required this.name, this.classId});

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'class_id': classId,
      };

  factory Member.fromMap(Map<String, Object?> map) => Member(
        id: map['id'] as int?,
        name: map['name'] as String,
        classId: map['class_id'] as int?,
      );

  Member copyWith({int? id, String? name, int? classId}) => Member(
        id: id ?? this.id,
        name: name ?? this.name,
        classId: classId ?? this.classId,
      );
}
```

Create `lib/models/class_model.dart`:

```dart
class ClassModel {
  final int? id;
  final String name;
  final String startTime; // "HH:mm"
  final Set<int> operatingDays; // DateTime.weekday values: 1=Mon .. 7=Sun

  const ClassModel({
    this.id,
    required this.name,
    required this.startTime,
    required this.operatingDays,
  });

  bool operatesOn(DateTime date) => operatingDays.contains(date.weekday);

  DateTime startDateTimeFor(DateTime date) {
    final parts = startTime.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'start_time': startTime,
        'operating_days': operatingDays.join(','),
      };

  factory ClassModel.fromMap(Map<String, Object?> map) => ClassModel(
        id: map['id'] as int?,
        name: map['name'] as String,
        startTime: map['start_time'] as String,
        operatingDays: (map['operating_days'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .map(int.parse)
            .toSet(),
      );
}
```

Create `lib/models/attendance.dart`:

```dart
enum AttendanceStatus { present, late, absent }

class Attendance {
  final int? id;
  final int memberId;
  final String date; // "YYYY-MM-DD"
  final String? checkInTime; // ISO8601, null when auto-marked absent
  final AttendanceStatus status;

  const Attendance({
    this.id,
    required this.memberId,
    required this.date,
    this.checkInTime,
    required this.status,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'member_id': memberId,
        'date': date,
        'check_in_time': checkInTime,
        'status': status.name,
      };

  factory Attendance.fromMap(Map<String, Object?> map) => Attendance(
        id: map['id'] as int?,
        memberId: map['member_id'] as int,
        date: map['date'] as String,
        checkInTime: map['check_in_time'] as String?,
        status: AttendanceStatus.values.byName(map['status'] as String),
      );
}
```

Create `lib/models/device_binding.dart`:

```dart
class DeviceBinding {
  final int? id;
  final String deviceToken;
  final int memberId;

  const DeviceBinding({this.id, required this.deviceToken, required this.memberId});

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'device_token': deviceToken,
        'member_id': memberId,
      };

  factory DeviceBinding.fromMap(Map<String, Object?> map) => DeviceBinding(
        id: map['id'] as int?,
        deviceToken: map['device_token'] as String,
        memberId: map['member_id'] as int,
      );
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/models/models_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml lib/models test/models
git commit -m "feat: scaffold checkin_app and add data models"
```

---

## Task 2: Database schema + test helper

**Files:**
- Create: `lib/db/database_helper.dart`
- Create: `test/helpers/test_db.dart`
- Test: `test/db/database_helper_test.dart`

**Interfaces:**
- Consumes: nothing beyond Task 1's models (schema only, no model use here).
- Produces: `DatabaseHelper.open(String path) -> Future<Database>` (creates tables `classes`, `members`, `device_bindings`, `attendance`). `openTestDatabase() -> Future<Database>` test helper that returns an in-memory DB with the schema already applied — every later repository/service test imports this.

- [ ] **Step 1: Write the failing test**

Create `test/db/database_helper_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import '../helpers/test_db.dart';

void main() {
  test('opens an in-memory database with all four tables', () async {
    final db = await openTestDatabase();
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(names, containsAll(['classes', 'members', 'device_bindings', 'attendance']));
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/db/database_helper_test.dart`
Expected: FAIL — `lib/db/database_helper.dart` and `test/helpers/test_db.dart` don't exist yet.

- [ ] **Step 3: Implement the schema and test helper**

Create `lib/db/database_helper.dart`:

```dart
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
```

Create `test/helpers/test_db.dart`:

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/db/database_helper.dart';

Future<Database> openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return DatabaseHelper.open(inMemoryDatabasePath);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/db/database_helper_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/db test/helpers test/db
git commit -m "feat: add sqlite schema and in-memory test db helper"
```

---

## Task 3: Member & DeviceBinding repositories

**Files:**
- Create: `lib/repositories/member_repository.dart`
- Create: `lib/repositories/device_binding_repository.dart`
- Test: `test/repositories/member_repository_test.dart`
- Test: `test/repositories/device_binding_repository_test.dart`

**Interfaces:**
- Consumes: `Member`, `DeviceBinding` (Task 1), `openTestDatabase()` (Task 2).
- Produces: `MemberRepository(Database db)` with `insert(Member) -> Future<int>`, `update(Member) -> Future<void>`, `delete(int id) -> Future<void>`, `getById(int) -> Future<Member?>`, `getAll() -> Future<List<Member>>`, `getByClassId(int) -> Future<List<Member>>`. `DeviceBindingRepository(Database db)` with `bind(String deviceToken, int memberId) -> Future<void>` (insert-or-replace, keyed on unique `device_token`) and `getByToken(String) -> Future<DeviceBinding?>`.

- [ ] **Step 1: Write the failing tests**

Create `test/repositories/member_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import '../helpers/test_db.dart';

void main() {
  test('insert, fetch, update, and delete a member', () async {
    final db = await openTestDatabase();
    final repo = MemberRepository(db);

    final id = await repo.insert(const Member(name: '홍길동', classId: null));
    final fetched = await repo.getById(id);
    expect(fetched?.name, '홍길동');

    await repo.update(fetched!.copyWith(name: '김철수'));
    final updated = await repo.getById(id);
    expect(updated?.name, '김철수');

    await repo.delete(id);
    expect(await repo.getById(id), isNull);
    await db.close();
  });

  test('getByClassId returns only members in that class', () async {
    final db = await openTestDatabase();
    final repo = MemberRepository(db);
    await repo.insert(const Member(name: 'A', classId: 1));
    await repo.insert(const Member(name: 'B', classId: 1));
    await repo.insert(const Member(name: 'C', classId: 2));

    final classOne = await repo.getByClassId(1);
    expect(classOne.map((m) => m.name).toSet(), {'A', 'B'});
    await db.close();
  });
}
```

Create `test/repositories/device_binding_repository_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/repositories/member_repository_test.dart test/repositories/device_binding_repository_test.dart`
Expected: FAIL — repository files don't exist yet.

- [ ] **Step 3: Implement the repositories**

Create `lib/repositories/member_repository.dart`:

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/member.dart';

class MemberRepository {
  final Database db;
  MemberRepository(this.db);

  Future<int> insert(Member member) => db.insert('members', member.toMap());

  Future<void> update(Member member) => db.update(
        'members',
        member.toMap(),
        where: 'id = ?',
        whereArgs: [member.id],
      );

  Future<void> delete(int id) =>
      db.delete('members', where: 'id = ?', whereArgs: [id]);

  Future<Member?> getById(int id) async {
    final rows = await db.query('members', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Member.fromMap(rows.first);
  }

  Future<List<Member>> getAll() async {
    final rows = await db.query('members');
    return rows.map(Member.fromMap).toList();
  }

  Future<List<Member>> getByClassId(int classId) async {
    final rows =
        await db.query('members', where: 'class_id = ?', whereArgs: [classId]);
    return rows.map(Member.fromMap).toList();
  }
}
```

Create `lib/repositories/device_binding_repository.dart`:

```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/repositories/member_repository_test.dart test/repositories/device_binding_repository_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/member_repository.dart lib/repositories/device_binding_repository.dart test/repositories
git commit -m "feat: add member and device binding repositories"
```

---

## Task 4: Class repository

**Files:**
- Create: `lib/repositories/class_repository.dart`
- Test: `test/repositories/class_repository_test.dart`

**Interfaces:**
- Consumes: `ClassModel` (Task 1), `openTestDatabase()` (Task 2).
- Produces: `ClassRepository(Database db)` with `insert(ClassModel) -> Future<int>`, `update(ClassModel) -> Future<void>`, `delete(int id) -> Future<void>`, `getById(int) -> Future<ClassModel?>`, `getAll() -> Future<List<ClassModel>>`.

- [ ] **Step 1: Write the failing test**

Create `test/repositories/class_repository_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/class_repository_test.dart`
Expected: FAIL — `lib/repositories/class_repository.dart` doesn't exist yet.

- [ ] **Step 3: Implement the repository**

Create `lib/repositories/class_repository.dart`:

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/class_model.dart';

class ClassRepository {
  final Database db;
  ClassRepository(this.db);

  Future<int> insert(ClassModel classModel) =>
      db.insert('classes', classModel.toMap());

  Future<void> update(ClassModel classModel) => db.update(
        'classes',
        classModel.toMap(),
        where: 'id = ?',
        whereArgs: [classModel.id],
      );

  Future<void> delete(int id) =>
      db.delete('classes', where: 'id = ?', whereArgs: [id]);

  Future<ClassModel?> getById(int id) async {
    final rows = await db.query('classes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ClassModel.fromMap(rows.first);
  }

  Future<List<ClassModel>> getAll() async {
    final rows = await db.query('classes');
    return rows.map(ClassModel.fromMap).toList();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/class_repository_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/class_repository.dart test/repositories/class_repository_test.dart
git commit -m "feat: add class repository"
```

---

## Task 5: Attendance repository

**Files:**
- Create: `lib/repositories/attendance_repository.dart`
- Test: `test/repositories/attendance_repository_test.dart`

**Interfaces:**
- Consumes: `Attendance`, `AttendanceStatus` (Task 1), `openTestDatabase()` (Task 2).
- Produces: `AttendanceRepository(Database db)` with `getByMemberAndDate(int memberId, String date) -> Future<Attendance?>`, `insert(Attendance) -> Future<int>` (ignores insert on conflict — the `UNIQUE(member_id, date)` constraint makes this idempotent), `getByDate(String date) -> Future<List<Attendance>>`, `getHistoryForMember(int memberId) -> Future<List<Attendance>>` (newest first).

- [ ] **Step 1: Write the failing test**

Create `test/repositories/attendance_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import '../helpers/test_db.dart';

void main() {
  test('insert then getByMemberAndDate returns the record', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(const Attendance(
      memberId: 1,
      date: '2026-09-18',
      checkInTime: '2026-09-18T15:05:00.000',
      status: AttendanceStatus.present,
    ));

    final found = await repo.getByMemberAndDate(1, '2026-09-18');
    expect(found?.status, AttendanceStatus.present);
    expect(await repo.getByMemberAndDate(1, '2026-09-19'), isNull);
    await db.close();
  });

  test('insert is a no-op if a record already exists for member+date', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);

    await repo.insert(const Attendance(
      memberId: 1,
      date: '2026-09-18',
      checkInTime: '2026-09-18T15:05:00.000',
      status: AttendanceStatus.present,
    ));
    await repo.insert(const Attendance(
      memberId: 1,
      date: '2026-09-18',
      checkInTime: '2026-09-18T18:00:00.000',
      status: AttendanceStatus.late,
    ));

    final found = await repo.getByMemberAndDate(1, '2026-09-18');
    expect(found?.status, AttendanceStatus.present); // first write wins
    await db.close();
  });

  test('getByDate returns all records for that date across members', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    await repo.insert(const Attendance(
        memberId: 1, date: '2026-09-18', checkInTime: null, status: AttendanceStatus.present));
    await repo.insert(const Attendance(
        memberId: 2, date: '2026-09-18', checkInTime: null, status: AttendanceStatus.absent));
    await repo.insert(const Attendance(
        memberId: 1, date: '2026-09-19', checkInTime: null, status: AttendanceStatus.present));

    final records = await repo.getByDate('2026-09-18');
    expect(records.map((a) => a.memberId).toSet(), {1, 2});
    await db.close();
  });

  test('getHistoryForMember returns newest first', () async {
    final db = await openTestDatabase();
    final repo = AttendanceRepository(db);
    await repo.insert(const Attendance(
        memberId: 1, date: '2026-09-01', checkInTime: null, status: AttendanceStatus.present));
    await repo.insert(const Attendance(
        memberId: 1, date: '2026-09-18', checkInTime: null, status: AttendanceStatus.late));

    final history = await repo.getHistoryForMember(1);
    expect(history.first.date, '2026-09-18');
    expect(history.last.date, '2026-09-01');
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/attendance_repository_test.dart`
Expected: FAIL — `lib/repositories/attendance_repository.dart` doesn't exist yet.

- [ ] **Step 3: Implement the repository**

Create `lib/repositories/attendance_repository.dart`:

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/attendance.dart';

class AttendanceRepository {
  final Database db;
  AttendanceRepository(this.db);

  Future<Attendance?> getByMemberAndDate(int memberId, String date) async {
    final rows = await db.query(
      'attendance',
      where: 'member_id = ? AND date = ?',
      whereArgs: [memberId, date],
    );
    if (rows.isEmpty) return null;
    return Attendance.fromMap(rows.first);
  }

  Future<int> insert(Attendance attendance) => db.insert(
        'attendance',
        attendance.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  Future<List<Attendance>> getByDate(String date) async {
    final rows = await db.query('attendance', where: 'date = ?', whereArgs: [date]);
    return rows.map(Attendance.fromMap).toList();
  }

  Future<List<Attendance>> getHistoryForMember(int memberId) async {
    final rows = await db.query(
      'attendance',
      where: 'member_id = ?',
      whereArgs: [memberId],
      orderBy: 'date DESC',
    );
    return rows.map(Attendance.fromMap).toList();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/attendance_repository_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/attendance_repository.dart test/repositories/attendance_repository_test.dart
git commit -m "feat: add attendance repository"
```

---

## Task 6: AttendanceService (status determination, check-in, auto-absence)

**Files:**
- Create: `lib/services/attendance_service.dart`
- Test: `test/services/attendance_service_test.dart`

**Interfaces:**
- Consumes: `MemberRepository`, `ClassRepository`, `AttendanceRepository` (Tasks 3-5).
- Produces: `AttendanceService({required memberRepository, required classRepository, required attendanceRepository, Duration gracePeriod = Duration(minutes: 10)})` with `static formatDate(DateTime) -> String` ("YYYY-MM-DD"), `determineStatus(DateTime classStart, DateTime checkInTime) -> AttendanceStatus`, `recordCheckIn(int memberId, {DateTime? now}) -> Future<Attendance>` (idempotent per day), `markAbsentees(DateTime date) -> Future<int>` (returns count marked, only for classes operating that weekday).

- [ ] **Step 1: Write the failing test**

Create `test/services/attendance_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/attendance_service.dart';
import '../helpers/test_db.dart';

void main() {
  test('determineStatus is present exactly at the grace boundary, late after it', () async {
    final db = await openTestDatabase();
    final service = AttendanceService(
      memberRepository: MemberRepository(db),
      classRepository: ClassRepository(db),
      attendanceRepository: AttendanceRepository(db),
    );
    final classStart = DateTime(2026, 9, 18, 15, 0);

    expect(
      service.determineStatus(classStart, DateTime(2026, 9, 18, 15, 5)),
      AttendanceStatus.present,
    );
    expect(
      service.determineStatus(classStart, classStart.add(const Duration(minutes: 10))),
      AttendanceStatus.present, // exactly at the boundary still counts as present
    );
    expect(
      service.determineStatus(classStart, classStart.add(const Duration(minutes: 10, seconds: 1))),
      AttendanceStatus.late,
    );
    await db.close();
  });

  test('recordCheckIn marks present/late based on the member\'s class, and is idempotent', () async {
    final db = await openTestDatabase();
    final classRepo = ClassRepository(db);
    final memberRepo = MemberRepository(db);
    final attendanceRepo = AttendanceRepository(db);
    final service = AttendanceService(
      memberRepository: memberRepo,
      classRepository: classRepo,
      attendanceRepository: attendanceRepo,
    );

    final classId = await classRepo.insert(
      ClassModel(name: '국어반', startTime: '15:00', operatingDays: {5}), // Friday
    );
    final memberId = await memberRepo.insert(Member(name: '홍길동', classId: classId));

    final onTime = DateTime(2026, 9, 18, 15, 3); // Friday
    final result = await service.recordCheckIn(memberId, now: onTime);
    expect(result.status, AttendanceStatus.present);

    // Second check-in the same day must not change the recorded status.
    final laterSameDay = DateTime(2026, 9, 18, 20, 0);
    final second = await service.recordCheckIn(memberId, now: laterSameDay);
    expect(second.status, AttendanceStatus.present);
    await db.close();
  });

  test('recordCheckIn marks present for a member with no class', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final service = AttendanceService(
      memberRepository: memberRepo,
      classRepository: ClassRepository(db),
      attendanceRepository: AttendanceRepository(db),
    );
    final memberId = await memberRepo.insert(const Member(name: '무소속', classId: null));

    final result = await service.recordCheckIn(memberId, now: DateTime(2026, 9, 18, 23, 0));
    expect(result.status, AttendanceStatus.present);
    await db.close();
  });

  test('markAbsentees only marks members of classes operating that weekday, skipping those already checked in', () async {
    final db = await openTestDatabase();
    final classRepo = ClassRepository(db);
    final memberRepo = MemberRepository(db);
    final attendanceRepo = AttendanceRepository(db);
    final service = AttendanceService(
      memberRepository: memberRepo,
      classRepository: classRepo,
      attendanceRepository: attendanceRepo,
    );

    final fridayClassId = await classRepo.insert(
      ClassModel(name: '금요반', startTime: '15:00', operatingDays: {5}),
    );
    final mondayClassId = await classRepo.insert(
      ClassModel(name: '월요반', startTime: '15:00', operatingDays: {1}),
    );
    final absentMemberId = await memberRepo.insert(Member(name: '결석자', classId: fridayClassId));
    final presentMemberId = await memberRepo.insert(Member(name: '출석자', classId: fridayClassId));
    final mondayMemberId = await memberRepo.insert(Member(name: '월요일회원', classId: mondayClassId));

    final friday = DateTime(2026, 9, 18); // Friday
    await service.recordCheckIn(presentMemberId, now: DateTime(2026, 9, 18, 15, 1));

    final markedCount = await service.markAbsentees(friday);
    expect(markedCount, 1); // only absentMemberId

    final absentRecord =
        await attendanceRepo.getByMemberAndDate(absentMemberId, AttendanceService.formatDate(friday));
    expect(absentRecord?.status, AttendanceStatus.absent);

    // The Monday-class member must not be touched on a Friday run.
    final mondayMemberRecords = await attendanceRepo.getHistoryForMember(mondayMemberId);
    expect(mondayMemberRecords, isEmpty);
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/attendance_service_test.dart`
Expected: FAIL — `lib/services/attendance_service.dart` doesn't exist yet.

- [ ] **Step 3: Implement the service**

Create `lib/services/attendance_service.dart`:

```dart
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';

class AttendanceService {
  final MemberRepository memberRepository;
  final ClassRepository classRepository;
  final AttendanceRepository attendanceRepository;
  final Duration gracePeriod;

  AttendanceService({
    required this.memberRepository,
    required this.classRepository,
    required this.attendanceRepository,
    this.gracePeriod = const Duration(minutes: 10),
  });

  static String formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  AttendanceStatus determineStatus(DateTime classStart, DateTime checkInTime) {
    return checkInTime.isAfter(classStart.add(gracePeriod))
        ? AttendanceStatus.late
        : AttendanceStatus.present;
  }

  Future<Attendance> recordCheckIn(int memberId, {DateTime? now}) async {
    final checkInTime = now ?? DateTime.now();
    final dateKey = formatDate(checkInTime);

    final existing = await attendanceRepository.getByMemberAndDate(memberId, dateKey);
    if (existing != null) return existing;

    final member = await memberRepository.getById(memberId);
    if (member == null) {
      throw ArgumentError('Unknown member id: $memberId');
    }

    var status = AttendanceStatus.present;
    if (member.classId != null) {
      final classModel = await classRepository.getById(member.classId!);
      if (classModel != null) {
        status = determineStatus(classModel.startDateTimeFor(checkInTime), checkInTime);
      }
    }

    final attendance = Attendance(
      memberId: memberId,
      date: dateKey,
      checkInTime: checkInTime.toIso8601String(),
      status: status,
    );
    final id = await attendanceRepository.insert(attendance);
    return Attendance(
      id: id,
      memberId: memberId,
      date: dateKey,
      checkInTime: attendance.checkInTime,
      status: status,
    );
  }

  Future<int> markAbsentees(DateTime date) async {
    final dateKey = formatDate(date);
    final classes = await classRepository.getAll();
    var markedCount = 0;
    for (final classModel in classes) {
      if (classModel.id == null || !classModel.operatesOn(date)) continue;
      final members = await memberRepository.getByClassId(classModel.id!);
      for (final member in members) {
        if (member.id == null) continue;
        final existing = await attendanceRepository.getByMemberAndDate(member.id!, dateKey);
        if (existing != null) continue;
        await attendanceRepository.insert(Attendance(
          memberId: member.id!,
          date: dateKey,
          checkInTime: null,
          status: AttendanceStatus.absent,
        ));
        markedCount++;
      }
    }
    return markedCount;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/attendance_service_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/attendance_service.dart test/services/attendance_service_test.dart
git commit -m "feat: add attendance service with status rules and auto-absence"
```

---

## Task 7: QrTokenService (rotating check-in token)

**Files:**
- Create: `lib/services/qr_token_service.dart`
- Test: `test/services/qr_token_service_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart, no DB).
- Produces: `QrTokenService({Duration validityDuration = Duration(seconds: 30), Duration graceDuration = Duration(seconds: 10)})` with `String rotate()`, `String get currentToken`, `bool isValid(String token, {DateTime? now})`.

- [ ] **Step 1: Write the failing test**

Create `test/services/qr_token_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/qr_token_service.dart';

void main() {
  test('currentToken is non-empty and valid', () {
    final service = QrTokenService();
    expect(service.currentToken, isNotEmpty);
    expect(service.isValid(service.currentToken), isTrue);
  });

  test('rotate() produces a different token, and the old one is invalid outright as "current"', () {
    final service = QrTokenService();
    final first = service.currentToken;
    final second = service.rotate();
    expect(second, isNot(first));
    expect(service.isValid(second), isTrue);
  });

  test('the previous token stays valid within the grace window after rotation', () {
    final service = QrTokenService(graceDuration: const Duration(seconds: 10));
    final first = service.currentToken;
    final rotatedAt = DateTime(2026, 9, 18, 12, 0, 0);
    service.rotate();

    expect(
      service.isValid(first, now: rotatedAt.add(const Duration(seconds: 5))),
      isTrue,
    );
  });

  test('the previous token is rejected once the grace window elapses', () {
    final service = QrTokenService(graceDuration: const Duration(seconds: 10));
    final first = service.currentToken;
    final rotatedAt = DateTime(2026, 9, 18, 12, 0, 0);
    service.rotate();

    expect(
      service.isValid(first, now: rotatedAt.add(const Duration(seconds: 11))),
      isFalse,
    );
  });

  test('an unrelated token is always invalid', () {
    final service = QrTokenService();
    expect(service.isValid('not-a-real-token'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/qr_token_service_test.dart`
Expected: FAIL — `lib/services/qr_token_service.dart` doesn't exist yet.

- [ ] **Step 3: Implement the service**

Create `lib/services/qr_token_service.dart`:

```dart
import 'dart:math';

class QrTokenService {
  final Duration validityDuration;
  final Duration graceDuration;

  String? _currentToken;
  String? _previousToken;
  DateTime? _rotatedAt;
  final Random _random = Random.secure();

  QrTokenService({
    this.validityDuration = const Duration(seconds: 30),
    this.graceDuration = const Duration(seconds: 10),
  });

  String get currentToken {
    _currentToken ??= _generateToken();
    return _currentToken!;
  }

  String rotate() {
    _previousToken = _currentToken;
    _currentToken = _generateToken();
    _rotatedAt = DateTime.now();
    return _currentToken!;
  }

  bool isValid(String token, {DateTime? now}) {
    if (token == currentToken) return true;
    if (token == _previousToken && _rotatedAt != null) {
      final checkTime = now ?? DateTime.now();
      return checkTime.isBefore(_rotatedAt!.add(graceDuration));
    }
    return false;
  }

  String _generateToken() =>
      List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/qr_token_service_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/qr_token_service.dart test/services/qr_token_service_test.dart
git commit -m "feat: add rotating qr token service"
```

---

## Task 8: NetworkInfo + CheckInServer read endpoints

**Files:**
- Create: `lib/services/network_info.dart`
- Create: `lib/server/checkin_server.dart`
- Test: `test/services/network_info_test.dart`
- Test: `test/server/checkin_server_read_test.dart`

**Interfaces:**
- Consumes: `MemberRepository`, `DeviceBindingRepository` (Task 3), `AttendanceService` (Task 6), `QrTokenService` (Task 7).
- Produces: `NetworkInfo` with `Future<String?> getLocalIPv4()`. `CheckInServer({required MemberRepository memberRepository, required DeviceBindingRepository deviceBindingRepository, required AttendanceService attendanceService, required QrTokenService qrTokenService})` with `Future<int> start({int port = 8080}) -> Future<int>` (returns actual bound port) and `Future<void> stop()`. Routes added this task: `GET /api/members`, `GET /api/device-status?deviceToken=`. `POST /api/checkin` and `GET /checkin` are added in Tasks 9-10 but the router is structured here so later tasks only add handlers.

- [ ] **Step 1: Write the failing tests**

Create `test/services/network_info_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/services/network_info.dart';

void main() {
  test('getLocalIPv4 returns null or a dotted-quad IPv4 address', () async {
    final info = NetworkInfo();
    final ip = await info.getLocalIPv4();
    if (ip != null) {
      expect(RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(ip), isTrue);
    }
  });
}
```

Create `test/server/checkin_server_read_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import '../helpers/test_db.dart';

void main() {
  test('GET /api/members lists members as {id, name} JSON', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    await memberRepo.insert(const Member(name: '홍길동', classId: null));

    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: DeviceBindingRepository(db),
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: QrTokenService(),
    );
    final port = await server.start(port: 0);

    final response = await http.get(Uri.parse('http://localhost:$port/api/members'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as List;
    expect(body.single['name'], '홍길동');

    await server.stop();
    await db.close();
  });

  test('GET /api/device-status reports unbound and bound devices', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final deviceRepo = DeviceBindingRepository(db);
    final memberId = await memberRepo.insert(const Member(name: '홍길동', classId: null));
    await deviceRepo.bind('device-1', memberId);

    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: deviceRepo,
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: QrTokenService(),
    );
    final port = await server.start(port: 0);

    final unbound =
        await http.get(Uri.parse('http://localhost:$port/api/device-status?deviceToken=unknown'));
    expect(jsonDecode(unbound.body)['bound'], isFalse);

    final bound =
        await http.get(Uri.parse('http://localhost:$port/api/device-status?deviceToken=device-1'));
    final boundBody = jsonDecode(bound.body);
    expect(boundBody['bound'], isTrue);
    expect(boundBody['memberName'], '홍길동');

    await server.stop();
    await db.close();
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/network_info_test.dart test/server/checkin_server_read_test.dart`
Expected: FAIL — `lib/services/network_info.dart` and `lib/server/checkin_server.dart` don't exist yet.

- [ ] **Step 3: Implement NetworkInfo and the server's read endpoints**

Create `lib/services/network_info.dart`:

```dart
import 'dart:io';

class NetworkInfo {
  Future<String?> getLocalIPv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }
}
```

Create `lib/server/checkin_server.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';

class CheckInServer {
  final MemberRepository memberRepository;
  final DeviceBindingRepository deviceBindingRepository;
  final AttendanceService attendanceService;
  final QrTokenService qrTokenService;

  HttpServer? _server;

  CheckInServer({
    required this.memberRepository,
    required this.deviceBindingRepository,
    required this.attendanceService,
    required this.qrTokenService,
  });

  Router get _router {
    final router = Router();
    router.get('/api/members', _handleGetMembers);
    router.get('/api/device-status', _handleDeviceStatus);
    return router;
  }

  Future<int> start({int port = 8080}) async {
    _server = await shelf_io.serve(_router, InternetAddress.anyIPv4, port);
    return _server!.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Response> _handleGetMembers(Request request) async {
    final members = await memberRepository.getAll();
    final json = members.map((m) => {'id': m.id, 'name': m.name}).toList();
    return Response.ok(jsonEncode(json), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleDeviceStatus(Request request) async {
    final deviceToken = request.url.queryParameters['deviceToken'];
    if (deviceToken == null) {
      return Response.ok(jsonEncode({'bound': false}), headers: {'content-type': 'application/json'});
    }
    final binding = await deviceBindingRepository.getByToken(deviceToken);
    if (binding == null) {
      return Response.ok(jsonEncode({'bound': false}), headers: {'content-type': 'application/json'});
    }
    final member = await memberRepository.getById(binding.memberId);
    return Response.ok(
      jsonEncode({'bound': true, 'memberId': binding.memberId, 'memberName': member?.name}),
      headers: {'content-type': 'application/json'},
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/network_info_test.dart test/server/checkin_server_read_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/network_info.dart lib/server/checkin_server.dart test/services/network_info_test.dart test/server/checkin_server_read_test.dart
git commit -m "feat: add local http server with member list and device status endpoints"
```

---

## Task 9: CheckInServer check-in endpoint (POST /api/checkin)

**Files:**
- Modify: `lib/server/checkin_server.dart`
- Test: `test/server/checkin_server_checkin_test.dart`

**Interfaces:**
- Consumes: everything from Task 8's `CheckInServer`, plus `AttendanceService.recordCheckIn` (Task 6) and `DeviceBindingRepository.bind` (Task 3).
- Produces: `POST /api/checkin` accepting JSON body `{token, deviceToken?, memberId?}`. Success: `200 {success: true, memberName, status}`. Failure: `400 {error: 'invalid_token'}` for a bad/expired QR token, `400 {error: 'member_required'}` when neither an already-bound device nor an explicit `memberId` is given.

- [ ] **Step 1: Write the failing test**

Create `test/server/checkin_server_checkin_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import '../helpers/test_db.dart';

Future<http.Response> _postCheckin(int port, Map<String, dynamic> body) {
  return http.post(
    Uri.parse('http://localhost:$port/api/checkin'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode(body),
  );
}

void main() {
  test('rejects an invalid token', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: DeviceBindingRepository(db),
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: QrTokenService(),
    );
    final port = await server.start(port: 0);

    final response = await _postCheckin(port, {'token': 'garbage'});
    expect(response.statusCode, 400);
    expect(jsonDecode(response.body)['error'], 'invalid_token');

    await server.stop();
    await db.close();
  });

  test('first-time check-in binds the device and records attendance', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final deviceRepo = DeviceBindingRepository(db);
    final qrTokenService = QrTokenService();
    final memberId = await memberRepo.insert(const Member(name: '홍길동', classId: null));

    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: deviceRepo,
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: qrTokenService,
    );
    final port = await server.start(port: 0);

    final response = await _postCheckin(port, {
      'token': qrTokenService.currentToken,
      'deviceToken': 'device-1',
      'memberId': memberId,
    });
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body);
    expect(body['success'], isTrue);
    expect(body['memberName'], '홍길동');

    final binding = await deviceRepo.getByToken('device-1');
    expect(binding?.memberId, memberId);

    await server.stop();
    await db.close();
  });

  test('a previously bound device checks in without resending memberId', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final deviceRepo = DeviceBindingRepository(db);
    final qrTokenService = QrTokenService();
    final memberId = await memberRepo.insert(const Member(name: '홍길동', classId: null));
    await deviceRepo.bind('device-1', memberId);

    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: deviceRepo,
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: qrTokenService,
    );
    final port = await server.start(port: 0);

    final response =
        await _postCheckin(port, {'token': qrTokenService.currentToken, 'deviceToken': 'device-1'});
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body)['memberName'], '홍길동');

    await server.stop();
    await db.close();
  });

  test('an unbound device with no memberId is rejected as member_required', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final qrTokenService = QrTokenService();
    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: DeviceBindingRepository(db),
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: qrTokenService,
    );
    final port = await server.start(port: 0);

    final response =
        await _postCheckin(port, {'token': qrTokenService.currentToken, 'deviceToken': 'device-1'});
    expect(response.statusCode, 400);
    expect(jsonDecode(response.body)['error'], 'member_required');

    await server.stop();
    await db.close();
  });

  test('explicitly switching member rebinds the device', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final deviceRepo = DeviceBindingRepository(db);
    final qrTokenService = QrTokenService();
    final memberA = await memberRepo.insert(const Member(name: 'A', classId: null));
    final memberB = await memberRepo.insert(const Member(name: 'B', classId: null));
    await deviceRepo.bind('device-1', memberA);

    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: deviceRepo,
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: qrTokenService,
    );
    final port = await server.start(port: 0);

    final response = await _postCheckin(
      port,
      {'token': qrTokenService.currentToken, 'deviceToken': 'device-1', 'memberId': memberB},
    );
    expect(jsonDecode(response.body)['memberName'], 'B');
    final binding = await deviceRepo.getByToken('device-1');
    expect(binding?.memberId, memberB);

    await server.stop();
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/server/checkin_server_checkin_test.dart`
Expected: FAIL — `POST /api/checkin` route doesn't exist yet (404).

- [ ] **Step 3: Implement the check-in endpoint**

In `lib/server/checkin_server.dart`, add the route and handler:

Update `_router` to register the new route:

```dart
  Router get _router {
    final router = Router();
    router.get('/api/members', _handleGetMembers);
    router.get('/api/device-status', _handleDeviceStatus);
    router.post('/api/checkin', _handleCheckIn);
    return router;
  }
```

Add the handler method:

```dart
  Future<Response> _handleCheckIn(Request request) async {
    final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final token = payload['token'] as String?;
    final deviceToken = payload['deviceToken'] as String?;
    final memberId = payload['memberId'] as int?;

    if (token == null || !qrTokenService.isValid(token)) {
      return Response(400,
          body: jsonEncode({'error': 'invalid_token'}), headers: {'content-type': 'application/json'});
    }

    int resolvedMemberId;
    if (deviceToken != null && memberId != null) {
      await deviceBindingRepository.bind(deviceToken, memberId);
      resolvedMemberId = memberId;
    } else if (deviceToken != null) {
      final existing = await deviceBindingRepository.getByToken(deviceToken);
      if (existing == null) {
        return Response(400,
            body: jsonEncode({'error': 'member_required'}),
            headers: {'content-type': 'application/json'});
      }
      resolvedMemberId = existing.memberId;
    } else if (memberId != null) {
      resolvedMemberId = memberId;
    } else {
      return Response(400,
          body: jsonEncode({'error': 'member_required'}), headers: {'content-type': 'application/json'});
    }

    final attendance = await attendanceService.recordCheckIn(resolvedMemberId);
    final member = await memberRepository.getById(resolvedMemberId);
    return Response.ok(
      jsonEncode({'success': true, 'memberName': member?.name, 'status': attendance.status.name}),
      headers: {'content-type': 'application/json'},
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/server/checkin_server_checkin_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/server/checkin_server.dart test/server/checkin_server_checkin_test.dart
git commit -m "feat: add checkin endpoint with token validation and device binding"
```

---

## Task 10: Check-in web page + serving route

**Files:**
- Create: `lib/server/checkin_page.dart`
- Modify: `lib/server/checkin_server.dart`
- Test: `test/server/checkin_page_route_test.dart`

**Interfaces:**
- Consumes: `CheckInServer` (Tasks 8-9).
- Produces: `const String checkInPageHtml` (a self-contained HTML+JS page). `GET /checkin` on `CheckInServer` serves it with `content-type: text/html`.

- [ ] **Step 1: Write the failing test**

Create `test/server/checkin_page_route_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import '../helpers/test_db.dart';

void main() {
  test('GET /checkin serves the check-in HTML page', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: DeviceBindingRepository(db),
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: QrTokenService(),
    );
    final port = await server.start(port: 0);

    final response = await http.get(Uri.parse('http://localhost:$port/checkin?token=abc'));
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], contains('text/html'));
    expect(response.body, contains('id="checkin-app"'));
    expect(response.body, contains('submitCheckIn'));

    await server.stop();
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/server/checkin_page_route_test.dart`
Expected: FAIL — `GET /checkin` doesn't exist yet (404).

- [ ] **Step 3: Implement the page and the route**

Create `lib/server/checkin_page.dart`:

```dart
const String checkInPageHtml = '''
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>출석 체크</title>
<style>
  body { font-family: sans-serif; padding: 24px; text-align: center; }
  button { display: block; width: 100%; padding: 16px; margin: 8px 0; font-size: 18px; }
  #status { font-size: 20px; margin-top: 24px; }
</style>
</head>
<body id="checkin-app">
<h1>출석 체크</h1>
<div id="status">확인 중...</div>
<div id="member-list"></div>
<button id="switch-btn" style="display:none;">다른 사람으로 체크</button>
<script>
function getToken() {
  return new URLSearchParams(window.location.search).get('token');
}
function getDeviceToken() {
  return localStorage.getItem('deviceToken');
}
function setDeviceInfo(token, name) {
  localStorage.setItem('deviceToken', token);
  localStorage.setItem('memberName', name);
}
function clearDeviceInfo() {
  localStorage.removeItem('deviceToken');
  localStorage.removeItem('memberName');
}
function showStatus(text) {
  document.getElementById('status').textContent = text;
}
async function submitCheckIn(memberId) {
  const qrToken = getToken();
  let deviceToken = getDeviceToken();
  if (!deviceToken) {
    deviceToken = crypto.randomUUID();
  }
  const res = await fetch('/api/checkin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: qrToken, deviceToken: deviceToken, memberId: memberId }),
  });
  const data = await res.json();
  if (res.ok && data.success) {
    setDeviceInfo(deviceToken, data.memberName);
    showStatus(data.memberName + '\\uB2D8 ' + data.status + ' \\uCC98\\uB9AC\\uB418\\uC5C8\\uC2B5\\uB2C8\\uB2E4.');
    document.getElementById('member-list').innerHTML = '';
    document.getElementById('switch-btn').style.display = 'block';
  } else {
    showStatus('\\uCCB4\\uD06C\\uC5D0 \\uC2E4\\uD328\\uD588\\uC2B5\\uB2C8\\uB2E4: ' + (data.error || 'unknown'));
  }
}
async function showMemberList() {
  const res = await fetch('/api/members');
  const members = await res.json();
  const container = document.getElementById('member-list');
  container.innerHTML = '';
  members.forEach(function (m) {
    const btn = document.createElement('button');
    btn.textContent = m.name;
    btn.onclick = function () { submitCheckIn(m.id); };
    container.appendChild(btn);
  });
  showStatus('\\uBCF8\\uC778 \\uC774\\uB984\\uC744 \\uC120\\uD0DD\\uD574\\uC8FC\\uC138\\uC694');
}
async function init() {
  const deviceToken = getDeviceToken();
  if (deviceToken) {
    const res = await fetch('/api/device-status?deviceToken=' + encodeURIComponent(deviceToken));
    const data = await res.json();
    if (data.bound) {
      await submitCheckIn(data.memberId);
      return;
    }
  }
  await showMemberList();
}
document.getElementById('switch-btn').addEventListener('click', function () {
  clearDeviceInfo();
  document.getElementById('switch-btn').style.display = 'none';
  showMemberList();
});
init();
</script>
</body>
</html>
''';
```

(The `\\uXXXX` escapes spell out the Korean status/prompt strings so the Dart triple-quoted string has no literal non-ASCII surprises; they render as normal Korean text in the browser. If you'd rather keep the literal Korean characters in the source, that also works — just make sure the file is saved as UTF-8.)

In `lib/server/checkin_server.dart`, add the import:

```dart
import 'package:checkin_app/server/checkin_page.dart';
```

Register the route in `_router`:

```dart
    router.get('/checkin', _handleCheckInPage);
```

Add the handler:

```dart
  Future<Response> _handleCheckInPage(Request request) async {
    return Response.ok(checkInPageHtml, headers: {'content-type': 'text/html'});
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/server/checkin_page_route_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/server/checkin_page.dart lib/server/checkin_server.dart test/server/checkin_page_route_test.dart
git commit -m "feat: serve the student check-in web page"
```

---

## Task 11: CheckInAppController (QR rotation + server lifecycle)

**Files:**
- Create: `lib/services/checkin_app_controller.dart`
- Test: `test/services/checkin_app_controller_test.dart`

**Interfaces:**
- Consumes: `CheckInServer` (Tasks 8-10), `QrTokenService` (Task 7), `NetworkInfo` (Task 8).
- Produces: `CheckInAppController({required QrTokenService qrTokenService, required CheckInServer server, required NetworkInfo networkInfo, int port = 8080, Duration rotationInterval = Duration(seconds: 30)})` with `ValueNotifier<String?> qrUrl`, `Future<void> start()`, `Future<void> rotateNow()`, `Future<void> stop()`.

- [ ] **Step 1: Write the failing test**

Create `test/services/checkin_app_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import '../helpers/test_db.dart';

class _FixedNetworkInfo implements NetworkInfo {
  @override
  Future<String?> getLocalIPv4() async => '192.168.1.50';
}

void main() {
  test('start() binds the server, publishes a qrUrl with the current token, and rotateNow() changes it', () async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: DeviceBindingRepository(db),
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: AttendanceRepository(db),
      ),
      qrTokenService: QrTokenService(),
    );
    final controller = CheckInAppController(
      qrTokenService: QrTokenService(),
      server: server,
      networkInfo: _FixedNetworkInfo(),
      port: 0,
    );

    await controller.start();
    final firstUrl = controller.qrUrl.value;
    expect(firstUrl, isNotNull);
    expect(firstUrl, contains('192.168.1.50'));
    expect(firstUrl, contains('/checkin?token='));

    await controller.rotateNow();
    final secondUrl = controller.qrUrl.value;
    expect(secondUrl, isNot(firstUrl));

    await controller.stop();
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/checkin_app_controller_test.dart`
Expected: FAIL — `lib/services/checkin_app_controller.dart` doesn't exist yet.

- [ ] **Step 3: Implement the controller**

Create `lib/services/checkin_app_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/qr_token_service.dart';

class CheckInAppController {
  final QrTokenService qrTokenService;
  final CheckInServer server;
  final NetworkInfo networkInfo;
  final int port;
  final Duration rotationInterval;

  final ValueNotifier<String?> qrUrl = ValueNotifier(null);

  Timer? _rotationTimer;
  int? _boundPort;

  CheckInAppController({
    required this.qrTokenService,
    required this.server,
    required this.networkInfo,
    this.port = 8080,
    this.rotationInterval = const Duration(seconds: 30),
  });

  Future<void> start() async {
    _boundPort = await server.start(port: port);
    await rotateNow();
    _rotationTimer = Timer.periodic(rotationInterval, (_) => rotateNow());
  }

  Future<void> rotateNow() async {
    qrTokenService.rotate();
    final ip = await networkInfo.getLocalIPv4() ?? 'localhost';
    qrUrl.value = 'http://$ip:$_boundPort/checkin?token=${qrTokenService.currentToken}';
  }

  Future<void> stop() async {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    await server.stop();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/checkin_app_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/checkin_app_controller.dart test/services/checkin_app_controller_test.dart
git commit -m "feat: add checkin app controller tying together server and qr rotation"
```

---

## Task 12: Admin UI — Member management screen

**Files:**
- Create: `lib/ui/screens/member_management_screen.dart`
- Test: `test/ui/member_management_screen_test.dart`

**Interfaces:**
- Consumes: `MemberRepository`, `ClassRepository` (Tasks 3-4).
- Produces: `MemberManagementScreen({required MemberRepository memberRepository, required ClassRepository classRepository})`, a `StatefulWidget` rendering a member list with add/delete controls.

- [ ] **Step 1: Write the failing test**

Create `test/ui/member_management_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/ui/screens/member_management_screen.dart';
import '../helpers/test_db.dart';

void main() {
  testWidgets('adding a member shows it in the list', (tester) async {
    final db = await openTestDatabase();
    final classRepo = ClassRepository(db);
    final memberRepo = MemberRepository(db);
    await classRepo.insert(ClassModel(name: '국어반', startTime: '15:00', operatingDays: {1}));

    await tester.pumpWidget(MaterialApp(
      home: MemberManagementScreen(memberRepository: memberRepo, classRepository: classRepo),
    ));
    await tester.pumpAndSettle();

    expect(find.text('홍길동'), findsNothing);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '홍길동');
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    expect(find.text('홍길동'), findsOneWidget);
    await db.close();
  });

  testWidgets('deleting a member removes it from the list', (tester) async {
    final db = await openTestDatabase();
    final classRepo = ClassRepository(db);
    final memberRepo = MemberRepository(db);
    await memberRepo.insert(const Member(name: '삭제될사람', classId: null));

    await tester.pumpWidget(MaterialApp(
      home: MemberManagementScreen(memberRepository: memberRepo, classRepository: classRepo),
    ));
    await tester.pumpAndSettle();
    expect(find.text('삭제될사람'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('삭제될사람'), findsNothing);
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/member_management_screen_test.dart`
Expected: FAIL — `lib/ui/screens/member_management_screen.dart` doesn't exist yet.

- [ ] **Step 3: Implement the screen**

Create `lib/ui/screens/member_management_screen.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';

class MemberManagementScreen extends StatefulWidget {
  final MemberRepository memberRepository;
  final ClassRepository classRepository;

  const MemberManagementScreen({
    super.key,
    required this.memberRepository,
    required this.classRepository,
  });

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  List<Member> _members = [];
  List<ClassModel> _classes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final members = await widget.memberRepository.getAll();
    final classes = await widget.classRepository.getAll();
    if (!mounted) return;
    setState(() {
      _members = members;
      _classes = classes;
    });
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    int? selectedClassId = _classes.isNotEmpty ? _classes.first.id : null;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('회원 추가'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: '이름')),
              if (_classes.isNotEmpty)
                DropdownButton<int>(
                  value: selectedClassId,
                  items: _classes
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => selectedClassId = value),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await widget.memberRepository
                    .insert(Member(name: nameController.text, classId: selectedClassId));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _load();
              },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원 관리')),
      body: ListView.builder(
        itemCount: _members.length,
        itemBuilder: (context, index) {
          final member = _members[index];
          return ListTile(
            key: ValueKey('member_${member.id}'),
            title: Text(member.name),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                await widget.memberRepository.delete(member.id!);
                await _load();
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/member_management_screen_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/member_management_screen.dart test/ui/member_management_screen_test.dart
git commit -m "feat: add member management screen"
```

---

## Task 13: Admin UI — Class management screen

**Files:**
- Create: `lib/ui/screens/class_management_screen.dart`
- Test: `test/ui/class_management_screen_test.dart`

**Interfaces:**
- Consumes: `ClassRepository` (Task 4).
- Produces: `ClassManagementScreen({required ClassRepository classRepository})`, a `StatefulWidget` listing classes with add/delete controls (start time as text in `HH:mm`, operating days as day-of-week checkboxes).

- [ ] **Step 1: Write the failing test**

Create `test/ui/class_management_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/ui/screens/class_management_screen.dart';
import '../helpers/test_db.dart';

void main() {
  testWidgets('adding a class with name and start time shows it in the list', (tester) async {
    final db = await openTestDatabase();
    final classRepo = ClassRepository(db);

    await tester.pumpWidget(MaterialApp(
      home: ClassManagementScreen(classRepository: classRepo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('class_name_field')), '국어반');
    await tester.enterText(find.byKey(const ValueKey('class_time_field')), '15:00');
    await tester.tap(find.text('요일 1')); // toggles Monday (weekday 1)
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    expect(find.text('국어반'), findsOneWidget);
    await db.close();
  });

  testWidgets('deleting a class removes it from the list', (tester) async {
    final db = await openTestDatabase();
    final classRepo = ClassRepository(db);
    await classRepo.insert(ClassModel(name: '삭제될반', startTime: '10:00', operatingDays: {2}));

    await tester.pumpWidget(MaterialApp(
      home: ClassManagementScreen(classRepository: classRepo),
    ));
    await tester.pumpAndSettle();
    expect(find.text('삭제될반'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('삭제될반'), findsNothing);
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/class_management_screen_test.dart`
Expected: FAIL — `lib/ui/screens/class_management_screen.dart` doesn't exist yet.

- [ ] **Step 3: Implement the screen**

Create `lib/ui/screens/class_management_screen.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/repositories/class_repository.dart';

class ClassManagementScreen extends StatefulWidget {
  final ClassRepository classRepository;

  const ClassManagementScreen({super.key, required this.classRepository});

  @override
  State<ClassManagementScreen> createState() => _ClassManagementScreenState();
}

class _ClassManagementScreenState extends State<ClassManagementScreen> {
  List<ClassModel> _classes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final classes = await widget.classRepository.getAll();
    if (!mounted) return;
    setState(() => _classes = classes);
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final timeController = TextEditingController();
    final selectedDays = <int>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('반 추가'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('class_name_field'),
                controller: nameController,
                decoration: const InputDecoration(labelText: '반 이름'),
              ),
              TextField(
                key: const ValueKey('class_time_field'),
                controller: timeController,
                decoration: const InputDecoration(labelText: '시작 시간 (HH:mm)'),
              ),
              Wrap(
                children: List.generate(7, (i) {
                  final weekday = i + 1;
                  final selected = selectedDays.contains(weekday);
                  return FilterChip(
                    label: Text('요일 $weekday'),
                    selected: selected,
                    onSelected: (value) => setDialogState(() {
                      if (value) {
                        selectedDays.add(weekday);
                      } else {
                        selectedDays.remove(weekday);
                      }
                    }),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await widget.classRepository.insert(ClassModel(
                  name: nameController.text,
                  startTime: timeController.text,
                  operatingDays: selectedDays,
                ));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _load();
              },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('반 관리')),
      body: ListView.builder(
        itemCount: _classes.length,
        itemBuilder: (context, index) {
          final classModel = _classes[index];
          return ListTile(
            key: ValueKey('class_${classModel.id}'),
            title: Text(classModel.name),
            subtitle: Text('시작 ${classModel.startTime}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                await widget.classRepository.delete(classModel.id!);
                await _load();
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/class_management_screen_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/class_management_screen.dart test/ui/class_management_screen_test.dart
git commit -m "feat: add class management screen"
```

---

## Task 14: Admin UI — Live dashboard (QR + today's check-ins)

**Files:**
- Create: `lib/ui/screens/dashboard_screen.dart`
- Test: `test/ui/dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `CheckInAppController` (Task 11), `AttendanceRepository`, `MemberRepository` (Tasks 3, 5).
- Produces: `DashboardScreen({required CheckInAppController controller, required AttendanceRepository attendanceRepository, required MemberRepository memberRepository})` — shows a QR code built from `controller.qrUrl` and a list of today's checked-in members, refreshed on a timer.

- [ ] **Step 1: Write the failing test**

Create `test/ui/dashboard_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/ui/screens/dashboard_screen.dart';
import '../helpers/test_db.dart';

class _FixedNetworkInfo implements NetworkInfo {
  @override
  Future<String?> getLocalIPv4() async => '192.168.1.50';
}

void main() {
  testWidgets('shows a QR code and today\'s checked-in members', (tester) async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final attendanceRepo = AttendanceRepository(db);
    final memberId = await memberRepo.insert(const Member(name: '홍길동', classId: null));
    final today = AttendanceService.formatDate(DateTime.now());
    await attendanceRepo.insert(Attendance(
      memberId: memberId,
      date: today,
      checkInTime: DateTime.now().toIso8601String(),
      status: AttendanceStatus.present,
    ));

    final server = CheckInServer(
      memberRepository: memberRepo,
      deviceBindingRepository: DeviceBindingRepository(db),
      attendanceService: AttendanceService(
        memberRepository: memberRepo,
        classRepository: ClassRepository(db),
        attendanceRepository: attendanceRepo,
      ),
      qrTokenService: QrTokenService(),
    );
    final controller = CheckInAppController(
      qrTokenService: QrTokenService(),
      server: server,
      networkInfo: _FixedNetworkInfo(),
      port: 0,
    );
    await controller.start();

    await tester.pumpWidget(MaterialApp(
      home: DashboardScreen(
        controller: controller,
        attendanceRepository: attendanceRepo,
        memberRepository: memberRepo,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('홍길동'), findsOneWidget);

    await controller.stop();
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/dashboard_screen_test.dart`
Expected: FAIL — `lib/ui/screens/dashboard_screen.dart` doesn't exist yet.

- [ ] **Step 3: Implement the screen**

Create `lib/ui/screens/dashboard_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/checkin_app_controller.dart';

class DashboardScreen extends StatefulWidget {
  final CheckInAppController controller;
  final AttendanceRepository attendanceRepository;
  final MemberRepository memberRepository;

  const DashboardScreen({
    super.key,
    required this.controller,
    required this.attendanceRepository,
    required this.memberRepository,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<MapEntry<Attendance, Member>> _todayEntries = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final today = AttendanceService.formatDate(DateTime.now());
    final records = await widget.attendanceRepository.getByDate(today);
    final entries = <MapEntry<Attendance, Member>>[];
    for (final record in records) {
      final member = await widget.memberRepository.getById(record.memberId);
      if (member != null) entries.add(MapEntry(record, member));
    }
    if (!mounted) return;
    setState(() => _todayEntries = entries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('실시간 체크인 현황')),
      body: Row(
        children: [
          Expanded(
            child: Center(
              child: ValueListenableBuilder<String?>(
                valueListenable: widget.controller.qrUrl,
                builder: (context, url, _) {
                  if (url == null) return const CircularProgressIndicator();
                  return QrImageView(data: url, size: 240);
                },
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _todayEntries.length,
              itemBuilder: (context, index) {
                final entry = _todayEntries[index];
                return ListTile(
                  title: Text(entry.value.name),
                  trailing: Text(entry.key.status.name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/dashboard_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/dashboard_screen.dart test/ui/dashboard_screen_test.dart
git commit -m "feat: add live dashboard with qr code and today's check-ins"
```

---

## Task 15: Admin UI — Attendance history screen

**Files:**
- Create: `lib/ui/screens/attendance_history_screen.dart`
- Test: `test/ui/attendance_history_screen_test.dart`

**Interfaces:**
- Consumes: `MemberRepository`, `AttendanceRepository` (Tasks 3, 5).
- Produces: `AttendanceHistoryScreen({required MemberRepository memberRepository, required AttendanceRepository attendanceRepository})` — a member picker plus that member's full attendance history and a simple monthly present/late/absent count.

- [ ] **Step 1: Write the failing test**

Create `test/ui/attendance_history_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/ui/screens/attendance_history_screen.dart';
import '../helpers/test_db.dart';

void main() {
  testWidgets('selecting a member shows their attendance history', (tester) async {
    final db = await openTestDatabase();
    final memberRepo = MemberRepository(db);
    final attendanceRepo = AttendanceRepository(db);
    final memberId = await memberRepo.insert(const Member(name: '홍길동', classId: null));
    await attendanceRepo.insert(Attendance(
      memberId: memberId,
      date: '2026-09-18',
      checkInTime: '2026-09-18T15:05:00.000',
      status: AttendanceStatus.present,
    ));

    await tester.pumpWidget(MaterialApp(
      home: AttendanceHistoryScreen(memberRepository: memberRepo, attendanceRepository: attendanceRepo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('홍길동').last);
    await tester.pumpAndSettle();

    expect(find.text('2026-09-18'), findsOneWidget);
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/attendance_history_screen_test.dart`
Expected: FAIL — `lib/ui/screens/attendance_history_screen.dart` doesn't exist yet.

- [ ] **Step 3: Implement the screen**

Create `lib/ui/screens/attendance_history_screen.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final MemberRepository memberRepository;
  final AttendanceRepository attendanceRepository;

  const AttendanceHistoryScreen({
    super.key,
    required this.memberRepository,
    required this.attendanceRepository,
  });

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  List<Member> _members = [];
  int? _selectedMemberId;
  List<Attendance> _history = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final members = await widget.memberRepository.getAll();
    if (!mounted) return;
    setState(() => _members = members);
  }

  Future<void> _selectMember(int? memberId) async {
    setState(() => _selectedMemberId = memberId);
    if (memberId == null) return;
    final history = await widget.attendanceRepository.getHistoryForMember(memberId);
    if (!mounted) return;
    setState(() => _history = history);
  }

  @override
  Widget build(BuildContext context) {
    final presentCount = _history.where((a) => a.status == AttendanceStatus.present).length;
    final lateCount = _history.where((a) => a.status == AttendanceStatus.late).length;
    final absentCount = _history.where((a) => a.status == AttendanceStatus.absent).length;

    return Scaffold(
      appBar: AppBar(title: const Text('출석 기록')),
      body: Column(
        children: [
          DropdownButton<int>(
            value: _selectedMemberId,
            hint: const Text('회원 선택'),
            items: _members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
            onChanged: _selectMember,
          ),
          if (_selectedMemberId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('출석 $presentCount · 지각 $lateCount · 결석 $absentCount'),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final record = _history[index];
                return ListTile(
                  title: Text(record.date),
                  trailing: Text(record.status.name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/attendance_history_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/attendance_history_screen.dart test/ui/attendance_history_screen_test.dart
git commit -m "feat: add attendance history screen"
```

---

## Task 16: App shell wiring (main.dart, navigation, daily absence scheduler)

**Files:**
- Create: `lib/services/absence_scheduler.dart`
- Modify: `lib/main.dart`
- Test: `test/services/absence_scheduler_test.dart`
- Test: `test/main_smoke_test.dart`

**Interfaces:**
- Consumes: every class from Tasks 1-15.
- Produces: `AbsenceScheduler({required AttendanceService attendanceService, Duration checkInterval = Duration(hours: 1)})` with `void start({DateTime? now})`, `Future<void> checkNow({DateTime? now})`, `void stop()`. `main.dart` wires the database, repositories, services, controller, and a 3-tab navigation shell (Dashboard / Members / Classes / History).

- [ ] **Step 1: Write the failing test for the scheduler**

Create `test/services/absence_scheduler_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/models/class_model.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/services/absence_scheduler.dart';
import 'package:checkin_app/services/attendance_service.dart';
import '../helpers/test_db.dart';

void main() {
  test('marks yesterday\'s absentees the first time the date rolls over', () async {
    final db = await openTestDatabase();
    final classRepo = ClassRepository(db);
    final memberRepo = MemberRepository(db);
    final attendanceRepo = AttendanceRepository(db);
    final attendanceService = AttendanceService(
      memberRepository: memberRepo,
      classRepository: classRepo,
      attendanceRepository: attendanceRepo,
    );

    final fridayClassId = await classRepo.insert(
      ClassModel(name: '금요반', startTime: '15:00', operatingDays: {5}),
    );
    final memberId = await memberRepo.insert(Member(name: '결석자', classId: fridayClassId));

    final scheduler = AbsenceScheduler(attendanceService: attendanceService);
    final friday = DateTime(2026, 9, 18); // Friday
    final saturday = DateTime(2026, 9, 19);

    scheduler.start(now: friday); // first call just records the starting date, marks nothing
    var record = await attendanceRepo.getByMemberAndDate(memberId, AttendanceService.formatDate(friday));
    expect(record, isNull);

    await scheduler.checkNow(now: saturday); // date rolled over: yesterday (Friday) gets swept
    record = await attendanceRepo.getByMemberAndDate(memberId, AttendanceService.formatDate(friday));
    expect(record?.status, AttendanceStatus.absent);

    scheduler.stop();
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/absence_scheduler_test.dart`
Expected: FAIL — `lib/services/absence_scheduler.dart` doesn't exist yet.

- [ ] **Step 3: Implement the scheduler**

Create `lib/services/absence_scheduler.dart`:

```dart
import 'dart:async';

import 'package:checkin_app/services/attendance_service.dart';

class AbsenceScheduler {
  final AttendanceService attendanceService;
  final Duration checkInterval;

  String? _lastProcessedDate;
  Timer? _timer;

  AbsenceScheduler({
    required this.attendanceService,
    this.checkInterval = const Duration(hours: 1),
  });

  void start({DateTime? now}) {
    checkNow(now: now);
    _timer = Timer.periodic(checkInterval, (_) => checkNow());
  }

  Future<void> checkNow({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final today = AttendanceService.formatDate(current);

    if (_lastProcessedDate == null) {
      _lastProcessedDate = today;
      return;
    }
    if (_lastProcessedDate != today) {
      final yesterday = current.subtract(const Duration(days: 1));
      await attendanceService.markAbsentees(yesterday);
      _lastProcessedDate = today;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/absence_scheduler_test.dart`
Expected: PASS

- [ ] **Step 5: Write main.dart and a smoke test**

Create `test/main_smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_app/main.dart';

void main() {
  testWidgets('app builds a MaterialApp with a navigation shell', (tester) async {
    // dbPath: null => in-memory db; serverPort: 0 => ephemeral port, so this
    // test never fights another test (or a running app) for real port 8080.
    await tester.pumpWidget(const CheckInApp(dbPath: null, serverPort: 0));
    await tester.pumpAndSettle();
    expect(find.text('실시간 체크인 현황'), findsOneWidget);
  });
}
```

Run: `flutter test test/main_smoke_test.dart`
Expected: FAIL — `CheckInApp` widget doesn't exist yet.

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:checkin_app/db/database_helper.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/absence_scheduler.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/ui/screens/attendance_history_screen.dart';
import 'package:checkin_app/ui/screens/class_management_screen.dart';
import 'package:checkin_app/ui/screens/dashboard_screen.dart';
import 'package:checkin_app/ui/screens/member_management_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final supportDir = await getApplicationSupportDirectory();
  final dbPath = p.join(supportDir.path, 'checkin_app.db');

  runApp(CheckInApp(dbPath: dbPath));
}

class CheckInApp extends StatefulWidget {
  /// Pass null to use an in-memory database (used by widget/smoke tests).
  final String? dbPath;

  /// Port for the embedded check-in server. Tests should pass 0 (ephemeral)
  /// so they never fight over the real port 8080.
  final int serverPort;

  const CheckInApp({super.key, required this.dbPath, this.serverPort = 8080});

  @override
  State<CheckInApp> createState() => _CheckInAppState();
}

class _CheckInAppState extends State<CheckInApp> {
  MemberRepository? _memberRepository;
  ClassRepository? _classRepository;
  AttendanceRepository? _attendanceRepository;
  CheckInAppController? _controller;
  AbsenceScheduler? _absenceScheduler;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final db = await DatabaseHelper.open(widget.dbPath ?? inMemoryDatabasePath);
    final memberRepository = MemberRepository(db);
    final classRepository = ClassRepository(db);
    final attendanceRepository = AttendanceRepository(db);
    final deviceBindingRepository = DeviceBindingRepository(db);
    final attendanceService = AttendanceService(
      memberRepository: memberRepository,
      classRepository: classRepository,
      attendanceRepository: attendanceRepository,
    );
    final server = CheckInServer(
      memberRepository: memberRepository,
      deviceBindingRepository: deviceBindingRepository,
      attendanceService: attendanceService,
      qrTokenService: QrTokenService(),
    );
    final controller = CheckInAppController(
      qrTokenService: QrTokenService(),
      server: server,
      networkInfo: NetworkInfo(),
      port: widget.serverPort,
    );
    await controller.start();

    final absenceScheduler = AbsenceScheduler(attendanceService: attendanceService);
    absenceScheduler.start();

    if (!mounted) return;
    setState(() {
      _memberRepository = memberRepository;
      _classRepository = classRepository;
      _attendanceRepository = attendanceRepository;
      _controller = controller;
      _absenceScheduler = absenceScheduler;
    });
  }

  @override
  void dispose() {
    _absenceScheduler?.stop();
    _controller?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memberRepository = _memberRepository;
    final classRepository = _classRepository;
    final attendanceRepository = _attendanceRepository;
    final controller = _controller;

    if (memberRepository == null ||
        classRepository == null ||
        attendanceRepository == null ||
        controller == null) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    return MaterialApp(
      title: 'CheckInApp',
      home: _HomeShell(
        controller: controller,
        memberRepository: memberRepository,
        classRepository: classRepository,
        attendanceRepository: attendanceRepository,
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  final CheckInAppController controller;
  final MemberRepository memberRepository;
  final ClassRepository classRepository;
  final AttendanceRepository attendanceRepository;

  const _HomeShell({
    required this.controller,
    required this.memberRepository,
    required this.classRepository,
    required this.attendanceRepository,
  });

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        controller: widget.controller,
        attendanceRepository: widget.attendanceRepository,
        memberRepository: widget.memberRepository,
      ),
      MemberManagementScreen(
        memberRepository: widget.memberRepository,
        classRepository: widget.classRepository,
      ),
      ClassManagementScreen(classRepository: widget.classRepository),
      AttendanceHistoryScreen(
        memberRepository: widget.memberRepository,
        attendanceRepository: widget.attendanceRepository,
      ),
    ];

    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: '현황'),
          NavigationDestination(icon: Icon(Icons.people), label: '회원'),
          NavigationDestination(icon: Icon(Icons.class_), label: '반'),
          NavigationDestination(icon: Icon(Icons.history), label: '기록'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/services/absence_scheduler_test.dart test/main_smoke_test.dart`
Expected: PASS

- [ ] **Step 7: Run the full test suite**

Run: `flutter test`
Expected: PASS — every test file from Tasks 1-16 passes together.

- [ ] **Step 8: Commit**

```bash
git add lib/main.dart lib/services/absence_scheduler.dart test/services/absence_scheduler_test.dart test/main_smoke_test.dart
git commit -m "feat: wire main.dart with navigation shell and daily absence scheduler"
```

---

## After all tasks: manual smoke test

- [ ] Run `flutter run -d windows`, confirm the app launches to the dashboard tab showing a QR code.
- [ ] Add a class and a member through their tabs, confirm they persist after restarting the app (re-run `flutter run -d windows`).
- [ ] On a phone connected to the same Wi-Fi/LAN as the PC, open the URL shown by the QR manually (or scan it) and confirm the member list appears, selecting a name shows a success message, and reopening that same URL immediately checks in again without asking for a name.
