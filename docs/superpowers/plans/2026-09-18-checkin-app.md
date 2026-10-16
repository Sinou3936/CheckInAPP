# CheckInApp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter Desktop (Windows) attendance-management app where an admin manages members/classes on a counter PC, and members record both arrival and departure from their own phone by scanning a rotating QR code shown on that PC, over the local network only. Each arrival and departure raises a parent-notification event.

**Architecture:** A single Flutter desktop app owns a local SQLite database and runs an embedded HTTP server (shelf) in-process. The admin UI reads/writes the database directly through repository classes. The embedded server exposes a tiny JSON API plus a static check-in web page that a member's phone opens after scanning the QR code; the page talks only to that local server, never to the internet.

**Tech Stack:** Flutter Desktop (Windows), Dart, `sqflite_common_ffi` (SQLite), `shelf` + `shelf_router` (embedded HTTP server), `qr_flutter` (QR rendering), `path_provider` (app data directory).

**Spec:** `2026-09-18-checkin-app-design.md` (repo root)

## Global Constraints

- No cloud/external hosting — the check-in server only ever binds to the local network (spec: "AWS 무료 티어 종료로 배제").
- Late-arrival grace period: 10 minutes after a class's start time (spec example value).
- QR token rotation interval: 30 seconds, with a 10-second overlap grace window for tokens that just rotated (spec example value).
- **등원용 QR 과 하원용 QR 이 따로 뜬다.** 스캔한 QR 이 의도를 결정하므로 서버는 등원/하원을
  추론하지 않는다. 두 QR 은 **서로 독립된 토큰 값**을 가진다 — 한 토큰에 종류를 파라미터로
  붙이면 등원 QR 값만 고쳐 하원을 위조할 수 있다.
- **하원도 등원과 같이 회전 QR 을 거친다** — 가짜 하원은 학부모에게 "자녀가 나갔다"는 거짓
  통보를 보내므로 현장 밖에서 찍는 것이 가능해서는 안 된다.
- **확인 세션 유효 시간: 5분.** QR 토큰은 페이지가 열릴 때 검증하고 그 스캔에 대한 세션을
  발급한다. 최초 1회 절차가 QR 갱신 주기(30초)보다 오래 걸려, 토큰만으로 검증하면 반드시
  실패한다.
- **하원 가능 창: 12시간.** 하원 QR 은 등원 시각이 12시간 이내인 열린 세션만 닫는다. 열린
  세션이 둘 이상이면 등원이 가장 최근인 것을 닫는다.
- **세션은 등원한 날짜에 귀속된다.** 자정을 넘겨 하원해도 등원한 날의 행에 기록하고, 저장되는
  하원 시각은 실제 시각(다음 날)이다.
- **한 회원은 하루에 한 번만 등원한다** (`UNIQUE(member_id, date)`). 하루 2회 이상 방문은
  스코프 밖.
- **최초 기기 바인딩은 이름 + 학부모 연락처 뒷 4자리로 확인한다.** 연락처가 등록되지 않은
  회원은 혼자 바인딩할 수 없고 관리자가 대행한다. 같은 기기 토큰에서 5회 연속 실패하면
  10분 차단한다. 회원 명단 조회에도 유효한 세션을 요구한다.
- **모든 바인딩은 append-only 로 기록된다** (`binding_logs`). 재바인딩으로 현재 매핑이
  덮어써져도 사칭 흔적이 남아야 한다.
- **관리자 보정은 학부모 알림을 발생시키지 않는다.** 알림은 학생이 QR 을 스캔하는 경로에서만
  나간다.
- **업종(학원/헬스장)별 분기 모드를 만들지 않는다.** QR 2개 방식이 양쪽에서 동일하게 동작한다.
- One member belongs to at most one class — multi-class membership is explicitly out of scope.
- Device identification uses an anonymous per-device token only — never a phone number.
- A member may carry a parent contact, stored solely as the recipient of notification events. (This reverses the original "store no real contact details" constraint; see the spec's 개정 이력.)
- **Parent notifications are recorded, not sent.** Emission goes through a `ParentNotifier` interface whose only implementation writes to `notification_logs`. No SMS/KakaoTalk provider is integrated in this plan.
- No admin login for the desktop app (counter-PC assumption from spec).
- All commands in this plan assume the working directory is the repository root.

---

## 진행 상황 및 개정 상태 (2026-10-16 기준)

**완료된 태스크: 1–4** (모델, 스키마, Member·DeviceBinding 저장소, Class 저장소).
커밋 기준으로 저장소에 반영되어 있다.

**이번 실행 범위는 Task 5–10 이다.** 2026-10-16 스펙 개정(등원/하원 QR 분리, 최초 본인 확인
강화, 세션 귀속 규칙)을 반영해 Task 5–10 의 본문을 전부 다시 썼다.

| 태스크 | 상태 |
|---|---|
| 1–4 | 완료 |
| **5–10** | **개정 완료 — 이번 실행 범위.** 2026-10-16 스펙 기준으로 본문이 최신이다 |
| 11, 12 | **개정 필요** — 체크인 엔드포인트와 페이지에 QR 2종·확인 세션·뒷 4자리 확인·알림 호출이 아직 없다 |
| 13 | **개정 필요** — QR 회전이 토큰 2종을 함께 돌려야 한다 |
| 14 | **개정 필요** — 회원 양식에 학부모 연락처 입력이 필요하다 |
| 15 | 개정 불필요 |
| 16, 17 | **개정 필요** — 하원 현황·미하원 표시, 출결 기록 보정, 바인딩 이력·알림 내역 화면 |
| 18 | **개정 필요** — 알림 서비스 배선, 결석 처리 따라잡기(`app_state`) |

> ⚠️ **11–18 의 본문은 아직 개정 전 설계를 서술한다.** 그대로 구현하면 QR 2종·확인 세션·
> 본인 확인·보정 기능이 빠진 결과물이 나온다. 각 태스크를 시작하기 전에 본문을 먼저 개정할 것.
> 스펙과 충돌하면 스펙이 이긴다 (`2026-09-18-checkin-app-design.md`).

---

## Review Focus

이번 범위(Task 5–10)의 태스크 테스트가 직접 다루지 않으면서, 쓰는 사람을 물 가능성이 높은
입력·상황들. 각 줄의 테스트는 그 코드를 소유한 태스크에 이미 넣어두었다.

- **자정을 넘긴 하원** — 23:50 등원 후 00:20 하원. 등원한 날짜의 행에 들어가야 하고, 다음 날
  행이 새로 생기거나 등원 없는 하원으로 기록되어서는 안 된다 (Task 6·7).
- **열린 세션이 둘인 상태의 하원** — 어제 안 닫힌 세션 + 오늘 등원. 오래된 쪽을 닫으면 어제
  방문에 엉뚱한 하원 시각이 붙고 거짓 알림까지 나간다. 최근 쪽을 닫아야 한다 (Task 6·7).
- **등원 없이 하원 QR 만 스캔** — 저녁 시각의 등원(지각)으로 잘못 기록되지 않고
  `noOpenSession` 으로 거부되어야 한다 (Task 7).
- **등원 QR 재스캔** — 하원으로 넘어가지 않고 기록도 바뀌지 않아야 한다. 이번 개정의 존재
  이유가 이 입력이다 (Task 7).
- **QR 갱신 주기를 넘긴 최초 1회 절차** — 이름 찾기 + 4자리 입력이 30초를 넘겨도 절차가
  깨지지 않아야 한다. 확인 세션이 이를 흡수한다 (Task 8·10).

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

## Task 5: 데이터 계층 보강 (하원·학부모 연락처·알림 로그·바인딩 이력)

> 2026-09-28 개정(하원, 학부모 알림)과 2026-10-16 개정(바인딩 이력, 결석 처리 따라잡기)이
> 요구하는 모델과 스키마를 한 번에 넓힌다. **아직 어디에도 실데이터가 없으므로 마이그레이션을
> 쓰지 않고 `onCreate` 의 CREATE TABLE 문을 직접 고친다.** 스키마를 두 번 건드리지 않기 위해
> 이번 범위(Task 5~10)에서 당장 쓰지 않는 `app_state` 테이블까지 여기서 함께 만든다.
>
> `pending_bindings` 테이블은 **만들지 않는다** — 2026-10-16 스펙 개정에서 관리자 승인 대기
> 방식을 채택하지 않기로 했다.

**Files:**
- Modify: `lib/models/attendance.dart` (하원 시각 추가)
- Modify: `lib/models/member.dart` (학부모 연락처 추가)
- Modify: `lib/models/device_binding.dart` (바인딩 시각 추가)
- Create: `lib/models/notification_log.dart`
- Create: `lib/models/binding_log.dart`
- Modify: `lib/db/database_helper.dart` (컬럼 3개 추가, 테이블 3개 추가)
- Modify: `lib/repositories/device_binding_repository.dart` (바인딩 시각 기록 + 이력 적재)
- Modify: `test/models/models_test.dart`
- Modify: `test/db/database_helper_test.dart`
- Modify: `test/repositories/device_binding_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 의 모델들, Task 2 의 스키마, Task 3 의 `DeviceBindingRepository`.
- Produces:
  - `Attendance` 에 `String? checkOutTime` (ISO8601, 아직 하원하지 않았으면 null)
  - `Member` 에 `String? parentContact`
  - `DeviceBinding` 에 `String boundAt` (ISO8601, 필수)
  - `enum NotificationKind { checkIn, checkOut }` 와
    `NotificationLog({int? id, required int memberId, required String occurredAt,
    required NotificationKind kind, String? recipient})`
  - `BindingLog({int? id, required String deviceToken, required int memberId,
    required String occurredAt})`
  - `DeviceBindingRepository.bind(String deviceToken, int memberId, {DateTime? now})` —
    현재 매핑을 갱신하면서 `binding_logs` 에 한 줄을 **덧붙인다**
  - 스키마: `attendance.check_out_time`, `members.parent_contact`,
    `device_bindings.bound_at`, 테이블 `notification_logs`, `binding_logs`, `app_state`
- 모든 모델은 기존대로 `toMap()` / `fromMap(Map<String,Object?>)` 을 갖는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`test/models/models_test.dart` 의 Member / Attendance / DeviceBinding 테스트를 새 필드까지
검증하도록 고치고, 모델 2개의 왕복 테스트를 추가한다. 테스트 이름과 단정은 다음과 같다.

```dart
test('Member 는 학부모 연락처를 포함해 왕복한다', () {
  const member = Member(id: 1, name: '홍길동', classId: 2, parentContact: '010-0000-0000');
  final restored = Member.fromMap(member.toMap());
  expect(restored.parentContact, '010-0000-0000');
});

test('Member 는 학부모 연락처가 없어도 왕복한다', () {
  const member = Member(id: 1, name: '홍길동', classId: null);
  expect(Member.fromMap(member.toMap()).parentContact, isNull);
});

test('Attendance 는 하원 전 상태(하원 시각 null)로 왕복한다', () {
  const attendance = Attendance(
    id: 1, memberId: 5, date: '2026-10-16',
    checkInTime: '2026-10-16T15:02:00.000', checkOutTime: null,
    status: AttendanceStatus.present,
  );
  final restored = Attendance.fromMap(attendance.toMap());
  expect(restored.checkInTime, '2026-10-16T15:02:00.000');
  expect(restored.checkOutTime, isNull);
});

test('Attendance 는 자정을 넘긴 하원 시각도 그대로 왕복한다', () {
  const attendance = Attendance(
    id: 1, memberId: 5, date: '2026-10-16',
    checkInTime: '2026-10-16T23:50:00.000', checkOutTime: '2026-10-17T00:20:00.000',
    status: AttendanceStatus.present,
  );
  final restored = Attendance.fromMap(attendance.toMap());
  expect(restored.date, '2026-10-16');
  expect(restored.checkOutTime, '2026-10-17T00:20:00.000');
});

test('DeviceBinding 은 바인딩 시각을 포함해 왕복한다', () {
  const binding = DeviceBinding(
    id: 1, deviceToken: 'abc123', memberId: 7, boundAt: '2026-10-16T15:00:00.000',
  );
  final restored = DeviceBinding.fromMap(binding.toMap());
  expect(restored.deviceToken, 'abc123');
  expect(restored.boundAt, '2026-10-16T15:00:00.000');
});

test('NotificationLog 는 왕복한다', () {
  const log = NotificationLog(
    id: 1, memberId: 7, occurredAt: '2026-10-16T18:30:00.000',
    kind: NotificationKind.checkOut, recipient: '010-0000-0000',
  );
  final restored = NotificationLog.fromMap(log.toMap());
  expect(restored.kind, NotificationKind.checkOut);
  expect(restored.recipient, '010-0000-0000');
});

test('BindingLog 는 왕복한다', () {
  const log = BindingLog(
    id: 1, deviceToken: 'abc123', memberId: 7, occurredAt: '2026-10-16T15:00:00.000',
  );
  final restored = BindingLog.fromMap(log.toMap());
  expect(restored.deviceToken, 'abc123');
  expect(restored.memberId, 7);
});
```

`test/db/database_helper_test.dart` 의 기대 테이블 목록에 `notification_logs`,
`binding_logs`, `app_state` 를 더하고 컬럼 확인 테스트를 덧붙인다.

```dart
test('체크아웃·알림·바인딩 이력에 필요한 컬럼이 있다', () async {
  final db = await openTestDatabase();
  Future<Set<Object?>> cols(String table) async =>
      (await db.rawQuery('PRAGMA table_info($table)')).map((r) => r['name']).toSet();

  expect(await cols('attendance'), contains('check_out_time'));
  expect(await cols('members'), contains('parent_contact'));
  expect(await cols('device_bindings'), contains('bound_at'));
  await db.close();
});
```

`test/repositories/device_binding_repository_test.dart` 에 두 개를 추가한다.

```dart
test('bind 는 바인딩 시각을 기록한다', () async {
  final db = await openTestDatabase();
  final repo = DeviceBindingRepository(db);
  await repo.bind('device-1', 42, now: DateTime(2026, 10, 16, 15, 0));
  final binding = await repo.getByToken('device-1');
  expect(binding!.boundAt, DateTime(2026, 10, 16, 15, 0).toIso8601String());
  await db.close();
});

test('재바인딩해도 이전 바인딩 이력이 남는다', () async {
  final db = await openTestDatabase();
  final repo = DeviceBindingRepository(db);
  await repo.bind('device-1', 42, now: DateTime(2026, 10, 16, 15, 0));
  await repo.bind('device-1', 99, now: DateTime(2026, 10, 16, 16, 0));

  expect((await repo.getByToken('device-1'))!.memberId, 99);
  final logs = await db.query('binding_logs', orderBy: 'occurred_at');
  expect(logs.map((r) => r['member_id']).toList(), [42, 99]);
  await db.close();
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test`
Expected: FAIL — `checkOutTime`/`parentContact`/`boundAt` 이름 없음,
`notification_log.dart`·`binding_log.dart` 없음, 새 테이블 없음.

- [ ] **Step 3: 모델 보강**

`Attendance` 에 `String? checkOutTime` (map 키 `check_out_time`), `Member` 에
`String? parentContact` (`parent_contact`), `DeviceBinding` 에 `String boundAt`
(`bound_at`, 필수) 를 추가한다. `Member.copyWith` 도 `parentContact` 를 받는다.

`lib/models/notification_log.dart` 와 `lib/models/binding_log.dart` 를 위의 Interfaces
시그니처대로 만든다. map 키는 각각 `member_id`/`occurred_at`/`kind`/`recipient` 와
`device_token`/`member_id`/`occurred_at`. `NotificationKind` 는 `kind.name` 으로 저장하고
`NotificationKind.values.byName(...)` 으로 읽는다.

- [ ] **Step 4: 스키마 보강**

`lib/db/database_helper.dart` 의 `onCreate` 에서 `members` 에 `parent_contact TEXT`,
`attendance` 에 `check_out_time TEXT`, `device_bindings` 에 `bound_at TEXT NOT NULL` 을
추가하고 테이블 3개를 새로 만든다.

```sql
CREATE TABLE notification_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  member_id INTEGER NOT NULL,
  occurred_at TEXT NOT NULL,
  kind TEXT NOT NULL,
  recipient TEXT,
  FOREIGN KEY (member_id) REFERENCES members (id)
)

CREATE TABLE binding_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_token TEXT NOT NULL,
  member_id INTEGER NOT NULL,
  occurred_at TEXT NOT NULL,
  FOREIGN KEY (member_id) REFERENCES members (id)
)

CREATE TABLE app_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
```

`binding_logs.device_token` 에는 UNIQUE 를 걸지 않는다 — 같은 기기가 여러 번 묶인 이력이
모두 남아야 사칭 흔적이 보존된다.

`app_state` 는 이번 범위에서 아무도 읽지 않는다. 이를 다루는 저장소는 자동 결석 처리
따라잡기를 구현하는 Task 18 에서 추가한다.

- [ ] **Step 5: `bind` 가 시각을 찍고 이력을 남기게 고치기**

`DeviceBindingRepository.bind(String deviceToken, int memberId, {DateTime? now})` 로
시그니처를 바꾼다. `now` 가 null 이면 `DateTime.now()`. 같은 호출 안에서 두 가지를 한다.

- `device_bindings` 를 기존처럼 `ConflictAlgorithm.replace` 로 갱신하면서 `bound_at` 에
  `now.toIso8601String()` 을 넣는다
- `binding_logs` 에 `BindingLog(deviceToken: ..., memberId: ..., occurredAt: ...).toMap()` 을
  `insert` 한다 (덮어쓰지 않고 쌓인다)

- [ ] **Step 6: 통과 확인**

Run: `flutter test`
Expected: PASS — Task 3·4 의 저장소 테스트는 `toMap`/`fromMap` 을 거치므로 수정 없이 통과한다.

- [ ] **Step 7: 커밋**

```bash
git add lib/models lib/db lib/repositories/device_binding_repository.dart test
git commit -m "feat: 하원 시각·학부모 연락처·알림 로그·바인딩 이력 스키마 추가"
```

---

## Task 6: AttendanceRepository (등원·하원·보정·미하원 조회)

> 2026-10-16 개정 반영. 개정 전 본문은 등원만 다루었다. 하원 기록과 "열린 세션" 조회가
> 이번 태스크의 핵심이며, **세션은 등원한 날짜의 행에 귀속된다**는 규칙이 여기서 구현된다.

**Files:**
- Create: `lib/repositories/attendance_repository.dart`
- Test: `test/repositories/attendance_repository_test.dart`

**Interfaces:**
- Consumes: `Attendance`, `AttendanceStatus` (Task 1·5), `openTestDatabase()` (Task 2).
- Produces: `AttendanceRepository(Database db)` 에
  - `Future<int> insert(Attendance)` — `ConflictAlgorithm.ignore`.
    `UNIQUE(member_id, date)` 덕분에 하루 한 행이 보장되고 첫 쓰기가 이긴다
  - `Future<void> update(Attendance)` — `id` 로 갱신. 하원 기록과 관리자 보정이 모두 이 경로
  - `Future<Attendance?> getByMemberAndDate(int memberId, String date)`
  - `Future<List<Attendance>> getByDate(String date)`
  - `Future<List<Attendance>> getHistoryForMember(int memberId)` — 최신 날짜 먼저
  - `Future<Attendance?> findOpenSession(int memberId, {required DateTime now, Duration window = const Duration(hours: 12)})`
    — 하원 시각이 비어 있고 등원 시각이 `now - window` 이후인 기록 중 **등원 시각이 가장
    최근인 것** 하나. 없으면 null
  - `Future<List<Attendance>> findUnclosedSessions({required DateTime now, Duration window = const Duration(hours: 12)})`
    — 등원 시각이 있고 하원 시각이 비어 있으며 등원으로부터 `window` 가 지난 기록 (= 관리자가
    보정해야 할 "미하원" 목록)

`check_in_time` 은 ISO8601 문자열이고 ISO8601 은 사전순 정렬이 시간순과 일치하므로,
두 조회 모두 경계 시각을 `toIso8601String()` 으로 만들어 SQL 비교에 그대로 쓴다.
`findOpenSession` 은 `ORDER BY check_in_time DESC LIMIT 1`.

- [ ] **Step 1: 실패하는 테스트 작성**

`test/repositories/attendance_repository_test.dart` 생성. 테스트 이름과 단정:

```dart
test('insert 후 getByMemberAndDate 로 찾을 수 있다', () async { /* status present, 다른 날짜는 null */ });

test('같은 회원·날짜로 두 번 insert 하면 첫 기록이 유지된다', () async { /* 두 번째 status late 를 넣어도 present */ });

test('getByDate 는 그 날짜의 모든 회원 기록을 돌려준다', () async { /* memberId {1,2} */ });

test('getHistoryForMember 는 최신 날짜를 먼저 돌려준다', () async { /* first.date '2026-10-16', last.date '2026-10-01' */ });

test('findOpenSession 은 12시간 이내의 열린 세션을 찾는다', () async {
  final repo = AttendanceRepository(db);
  await repo.insert(const Attendance(
    memberId: 1, date: '2026-10-16',
    checkInTime: '2026-10-16T15:00:00.000', checkOutTime: null,
    status: AttendanceStatus.present,
  ));
  final open = await repo.findOpenSession(1, now: DateTime(2026, 10, 16, 18, 0));
  expect(open!.date, '2026-10-16');
});

test('findOpenSession 은 12시간이 지난 세션을 찾지 않는다', () async {
  // 등원 09:00, 조회 22:00 (13시간 뒤) -> null
});

test('findOpenSession 은 이미 하원한 기록을 찾지 않는다', () async {
  // check_out_time 이 채워진 행만 있으면 null
});

test('findOpenSession 은 열린 세션이 둘이면 등원이 가장 최근인 것을 돌려준다', () async {
  // 2026-10-16T23:50 (열림) 과 2026-10-17T08:00 (열림) -> date '2026-10-17'
});

test('update 는 하원 시각을 채운다', () async {
  // insert 후 getByMemberAndDate 로 id 를 얻고, checkOutTime 을 넣어 update -> 다시 읽어 확인
});

test('findUnclosedSessions 는 12시간이 지난 미하원 기록만 돌려준다', () async {
  // 09:00 등원(열림) + 21:00 등원(열림) 을 다른 날짜로 넣고 09:00+13시간 시점에 조회
  // -> 오래된 것 하나만
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/repositories/attendance_repository_test.dart`
Expected: FAIL — `lib/repositories/attendance_repository.dart` 가 없다.

- [ ] **Step 3: 저장소 구현**

위 Interfaces 의 시그니처대로 `lib/repositories/attendance_repository.dart` 를 만든다.
Task 3·4 의 저장소와 같은 모양(생성자로 `Database` 를 받고 `toMap`/`fromMap` 으로만 왕복)을
따른다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/repositories/attendance_repository_test.dart`
Expected: PASS (10 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/repositories/attendance_repository.dart test/repositories/attendance_repository_test.dart
git commit -m "feat: 하원과 열린 세션 조회를 포함한 출결 저장소 추가"
```

---

## Task 7: AttendanceService (등원·하원 기록, 상태 판정, 자동 결석)

> 2026-10-16 개정 반영. 등원/하원을 **추론하지 않는다** — 어느 QR 을 스캔했는지가 호출하는
> 메서드를 결정하므로, 서비스는 `recordCheckIn` 과 `recordCheckOut` 을 따로 제공한다.
>
> **이 서비스는 학부모 알림을 발생시키지 않는다.** 알림은 학생이 QR 을 스캔하는 경로에서만
> 나가야 하고(스펙), 관리자 보정은 저장소를 직접 쓴다. 따라서 알림 호출은 결과를 보고
> 판단할 수 있는 서버 엔드포인트(Task 11)가 담당한다. 그래서 두 메서드는 "새로 기록했는지"를
> 호출자가 알 수 있는 결과 객체를 돌려준다.

**Files:**
- Create: `lib/services/attendance_service.dart`
- Test: `test/services/attendance_service_test.dart`

**Interfaces:**
- Consumes: `MemberRepository` (Task 3), `ClassRepository` (Task 4),
  `AttendanceRepository` (Task 6).
- Produces:
  - `enum CheckInStatus { recorded, alreadyCheckedIn }`
  - `enum CheckOutStatus { recorded, noOpenSession, alreadyCheckedOut }`
  - `class CheckInOutcome { final CheckInStatus status; final Attendance attendance; }`
  - `class CheckOutOutcome { final CheckOutStatus status; final Attendance? attendance; }`
  - `AttendanceService({required MemberRepository memberRepository,
    required ClassRepository classRepository,
    required AttendanceRepository attendanceRepository,
    Duration gracePeriod = const Duration(minutes: 10),
    Duration checkOutWindow = const Duration(hours: 12)})` 에
    - `static String formatDate(DateTime) -> String` ("YYYY-MM-DD")
    - `AttendanceStatus determineStatus(DateTime classStart, DateTime checkInTime)`
    - `Future<CheckInOutcome> recordCheckIn(int memberId, {DateTime? now})`
    - `Future<CheckOutOutcome> recordCheckOut(int memberId, {DateTime? now})`
    - `Future<int> markAbsentees(DateTime date)` — 처리한 건수

`recordCheckOut` 의 분기 규칙:
`findOpenSession` 이 세션을 찾으면 그 행의 하원 시각을 채우고 `recorded`.
못 찾았을 때, 오늘 날짜 행이 있고 그 행의 하원 시각이 채워져 있으면 `alreadyCheckedOut`,
그 밖에는 모두 `noOpenSession`.

- [ ] **Step 1: 실패하는 테스트 작성**

`test/services/attendance_service_test.dart` 생성. 테스트 이름과 단정:

```dart
test('determineStatus 는 유예 경계까지 출석, 그 뒤는 지각', () {
  // classStart 15:00, gracePeriod 10분
  // 15:05 -> present, 15:10 정확히 -> present, 15:10:01 -> late
});

test('recordCheckIn 은 반 시작 시각 기준으로 출석/지각을 정하고 recorded 를 돌려준다', () async {
  // 금요반 15:00, 금요일 15:03 등원 -> status recorded, attendance.status present
});

test('같은 날 두 번째 등원 스캔은 alreadyCheckedIn 이고 기록을 바꾸지 않는다', () async {
  // 15:03 등원 후 20:00 재스캔 -> CheckInStatus.alreadyCheckedIn, attendance.status 는 present 유지
});

test('반이 없는 회원의 등원은 출석으로 기록된다', () async {
  // 23:00 에 등원해도 present
});

test('recordCheckOut 은 열린 세션의 하원 시각을 채운다', () async {
  // 15:00 등원 -> 18:30 하원 -> recorded, checkOutTime 이 18:30
});

test('자정을 넘겨 하원해도 등원한 날짜의 행에 기록된다', () async {
  final service = /* ... */;
  await service.recordCheckIn(memberId, now: DateTime(2026, 10, 16, 23, 50));
  final outcome = await service.recordCheckOut(memberId, now: DateTime(2026, 10, 17, 0, 20));
  expect(outcome.status, CheckOutStatus.recorded);
  expect(outcome.attendance!.date, '2026-10-16');
  expect(outcome.attendance!.checkOutTime, DateTime(2026, 10, 17, 0, 20).toIso8601String());
});

test('열린 세션이 둘이면 가장 최근 등원을 닫고 과거 세션은 그대로 둔다', () async {
  await service.recordCheckIn(memberId, now: DateTime(2026, 10, 16, 23, 50));
  await service.recordCheckIn(memberId, now: DateTime(2026, 10, 17, 8, 0));
  final outcome = await service.recordCheckOut(memberId, now: DateTime(2026, 10, 17, 10, 0));
  expect(outcome.attendance!.date, '2026-10-17');
  final yesterday = await attendanceRepo.getByMemberAndDate(memberId, '2026-10-16');
  expect(yesterday!.checkOutTime, isNull);
});

test('등원으로부터 12시간이 지나면 하원으로 닫히지 않는다', () async {
  // 09:00 등원 -> 22:00 하원 시도 -> noOpenSession
});

test('등원 기록이 없으면 하원은 noOpenSession 이다', () async {
  // 등원 없이 recordCheckOut -> noOpenSession, attendance 는 null
});

test('이미 하원한 뒤 다시 하원 스캔하면 alreadyCheckedOut 이다', () async {
  // 15:00 등원, 18:00 하원, 18:05 재스캔 -> alreadyCheckedOut
});

test('markAbsentees 는 운영 요일의 미체크 회원만 결석 처리한다', () async {
  // 금요반/월요반, 금요일에 실행 -> 금요반 미체크 1명만 처리(반환값 1),
  // 이미 등원한 회원과 월요반 회원은 건드리지 않는다
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/services/attendance_service_test.dart`
Expected: FAIL — `lib/services/attendance_service.dart` 가 없다.

- [ ] **Step 3: 서비스 구현**

위 Interfaces 의 시그니처와 `recordCheckOut` 분기 규칙대로 구현한다.
`recordCheckIn` 은 기존 기록이 있으면 그것을 담아 `alreadyCheckedIn` 으로 돌려주고,
없으면 회원의 반을 찾아 `determineStatus` 로 상태를 정해 insert 한다. 반이 없거나 반을
찾지 못하면 `AttendanceStatus.present`. 존재하지 않는 회원 id 는 `ArgumentError`.
`markAbsentees` 는 `classRepository.getAll()` 을 돌며 `operatesOn(date)` 인 반의 회원 중
그날 기록이 없는 사람에게 `AttendanceStatus.absent` 행을 넣는다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/services/attendance_service_test.dart`
Expected: PASS (11 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/services/attendance_service.dart test/services/attendance_service_test.dart
git commit -m "feat: 등원·하원 기록과 상태 판정을 담은 출결 서비스 추가"
```

---

## Task 8: QrTokenService (등원·하원 2종 회전 토큰) + VerificationSessionService

> 2026-10-16 개정으로 **개정 대상이 되었다** (이전 계획서는 "개정 불필요"로 표시했다).
> 토큰이 2종으로 늘고, 확인 세션이 새로 들어온다.
>
> 두 QR 은 **서로 독립된 토큰 값**을 갖는다. 하나의 토큰에 종류를 파라미터로 붙이면 학생이
> 등원 QR 로 받은 값의 파라미터만 바꿔 하원을 위조할 수 있다 (스펙).
>
> 확인 세션이 필요한 이유: QR 토큰은 30초마다 갱신되는데 최초 1회 절차(이름 찾기 + 연락처
> 뒷 4자리 입력)는 그보다 오래 걸려, 토큰만으로 검증하면 **반드시** 실패한다. 페이지가 열릴
> 때 토큰을 검증해 5분짜리 세션을 발급하고, 이후 요청은 세션으로 처리한다. 세션은 유효한
> QR 을 스캔해야만 발급되므로 "카운터에 직접 와야 한다"는 보증은 유지된다.

**Files:**
- Create: `lib/services/qr_token_service.dart`
- Create: `lib/services/verification_session_service.dart`
- Test: `test/services/qr_token_service_test.dart`
- Test: `test/services/verification_session_service_test.dart`

**Interfaces:**
- Consumes: 없음 (순수 Dart, DB 접근 없음).
- Produces:
  - `enum QrKind { checkIn, checkOut }` — `lib/services/qr_token_service.dart` 에 둔다
  - `QrTokenService({Duration validityDuration = const Duration(seconds: 30),
    Duration graceDuration = const Duration(seconds: 10)})` 에
    - `String get checkInToken`
    - `String get checkOutToken`
    - `void rotate({DateTime? now})` — 두 토큰을 동시에 교체하고 직전 값을 유예 대상으로 남긴다
    - `QrKind? kindOf(String token, {DateTime? now})` — 유효하면 종류, 아니면 null
  - `VerificationSessionService({Duration ttl = const Duration(minutes: 5)})` 에
    - `String issue(QrKind kind, {DateTime? now})` — 세션 id 를 돌려준다
    - `QrKind? kindOf(String sessionId, {DateTime? now})` — 유효하면 종류, 아니면 null
    - `void consume(String sessionId)` — 사용 완료 처리. 이후 `kindOf` 는 null

토큰과 세션 id 는 `Random.secure()` 로 만든 16자 hex 를 쓴다 (Task 1~4 가 쓴 방식과 동일).

- [ ] **Step 1: 실패하는 테스트 작성**

`test/services/qr_token_service_test.dart`:

```dart
test('등원 토큰과 하원 토큰은 서로 다르다', () {
  final service = QrTokenService();
  expect(service.checkInToken, isNotEmpty);
  expect(service.checkOutToken, isNot(service.checkInToken));
});

test('kindOf 는 각 토큰의 종류를 돌려준다', () {
  final service = QrTokenService();
  expect(service.kindOf(service.checkInToken), QrKind.checkIn);
  expect(service.kindOf(service.checkOutToken), QrKind.checkOut);
});

test('rotate 는 두 토큰을 모두 교체한다', () {
  // rotate 전후의 checkInToken·checkOutToken 이 모두 달라지고, 새 값은 유효하다
});

test('직전 토큰은 유예 창 안에서 종류를 유지한 채 유효하다', () {
  final service = QrTokenService(graceDuration: const Duration(seconds: 10));
  final firstCheckIn = service.checkInToken;
  final rotatedAt = DateTime(2026, 10, 16, 12, 0, 0);
  service.rotate(now: rotatedAt);
  expect(
    service.kindOf(firstCheckIn, now: rotatedAt.add(const Duration(seconds: 5))),
    QrKind.checkIn,
  );
});

test('유예 창이 지나면 직전 토큰은 거부된다', () {
  // rotate 후 11초 뒤 kindOf -> null
});

test('모르는 토큰은 null 이다', () {
  expect(QrTokenService().kindOf('not-a-real-token'), isNull);
});
```

`test/services/verification_session_service_test.dart`:

```dart
test('발급한 세션은 종류를 돌려준다', () {
  final service = VerificationSessionService();
  final id = service.issue(QrKind.checkOut);
  expect(service.kindOf(id), QrKind.checkOut);
});

test('ttl 이 지난 세션은 거부된다', () {
  final service = VerificationSessionService(ttl: const Duration(minutes: 5));
  final issuedAt = DateTime(2026, 10, 16, 12, 0, 0);
  final id = service.issue(QrKind.checkIn, now: issuedAt);
  expect(service.kindOf(id, now: issuedAt.add(const Duration(minutes: 4))), QrKind.checkIn);
  expect(service.kindOf(id, now: issuedAt.add(const Duration(minutes: 6))), isNull);
});

test('consume 한 세션은 다시 쓸 수 없다', () {
  // issue -> consume -> kindOf null
});

test('모르는 세션은 null 이다', () {
  expect(VerificationSessionService().kindOf('nope'), isNull);
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/services/qr_token_service_test.dart test/services/verification_session_service_test.dart`
Expected: FAIL — 두 파일이 아직 없다.

- [ ] **Step 3: 두 서비스 구현**

위 Interfaces 의 시그니처대로 구현한다. `QrTokenService` 는 종류별로 현재 토큰과 직전 토큰,
그리고 마지막 `rotate` 시각을 들고 있다가 `kindOf` 에서 현재 값이면 즉시 종류를, 직전 값이면
`rotate` 시각 + `graceDuration` 안쪽일 때만 종류를 돌려준다.
`VerificationSessionService` 는 세션 id → (종류, 발급 시각) 맵을 들고 `ttl` 로 만료를 판정한다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/services/qr_token_service_test.dart test/services/verification_session_service_test.dart`
Expected: PASS (10 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/services/qr_token_service.dart lib/services/verification_session_service.dart test/services/qr_token_service_test.dart test/services/verification_session_service_test.dart
git commit -m "feat: 등원·하원 2종 회전 토큰과 확인 세션 서비스 추가"
```

---

## Task 9: 학부모 알림 서비스 (인터페이스 + 기록 구현체)

> 2026-09-28 설계 개정으로 들어온 태스크.
> **지금은 실제 문자/카톡을 보내지 않는다.** 발송 지점을 인터페이스로 만들어 두고,
> 이번 구현체는 알림 이벤트를 DB에 기록만 한다. 나중에 업체 계약이 되면 이 인터페이스
> 뒤에 실제 발송기를 갈아끼운다.
>
> 2026-10-16 개정이 더한 경계: **이 서비스를 호출하는 곳은 학생이 QR 을 스캔하는 경로뿐이다.**
> 관리자 보정은 저장소를 직접 쓰고 알림을 내지 않는다. 따라서 `NotificationService` 자체는
> "호출되면 기록한다"만 하고, 호출 여부 판단은 서버 엔드포인트(Task 11)가 한다.

**Files:**
- Create: `lib/repositories/notification_log_repository.dart`
- Create: `lib/services/notification_service.dart`
- Test: `test/services/notification_service_test.dart`

**Interfaces:**
- Consumes: `NotificationLog`, `NotificationKind` (Task 5), `MemberRepository` (Task 3),
  `openTestDatabase()` (Task 2).
- Produces:
  - `NotificationLogRepository(Database db)` 에 `Future<int> insert(NotificationLog)`,
    `Future<List<NotificationLog>> getRecent({int limit = 50})` (발생 시각 최신순)
  - `abstract class ParentNotifier` 에 `Future<void> notify(NotificationLog log)`
  - `RecordingParentNotifier(NotificationLogRepository)` — 그 구현체
  - `NotificationService({required MemberRepository memberRepository,
    required ParentNotifier notifier})` 에
    `Future<void> onCheckIn(int memberId, DateTime at)`,
    `Future<void> onCheckOut(int memberId, DateTime at)`

- [ ] **Step 1: 실패하는 테스트 작성**

`test/services/notification_service_test.dart` 생성. 테스트 이름과 단정:

```dart
test('등원 시 학부모 연락처를 수신처로 하는 알림이 기록된다', () async {
  // parentContact '010-1111-2222' 인 회원, onCheckIn(.., DateTime(2026,10,16,15,2))
  // -> logs 1건, kind checkIn, recipient '010-1111-2222',
  //    occurredAt == DateTime(2026,10,16,15,2).toIso8601String()
});

test('하원 시에도 알림이 기록된다', () async {
  // onCheckOut -> kind checkOut
});

test('학부모 연락처가 없어도 알림은 수신처 없이 기록된다', () async {
  // parentContact 없는 회원 -> recipient null
  // (관리자 화면이 "알림 대상 없음"을 볼 수 있어야 하므로 기록은 남긴다)
});

test('getRecent 는 최신 발생 순으로 돌려준다', () async {
  // 15:00 checkIn, 18:00 checkOut 을 넣고 first.kind checkOut, last.kind checkIn
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/services/notification_service_test.dart`
Expected: FAIL — 두 파일이 아직 없다.

- [ ] **Step 3: 저장소와 서비스 구현**

위 Interfaces 의 시그니처대로 만든다. `NotificationService` 는 회원을 조회해
`member?.parentContact` 를 수신처로 담은 `NotificationLog` 를 만들고 `notifier.notify` 에
넘긴다. 회원을 못 찾아도 예외를 던지지 않고 수신처 없이 기록한다.

`ParentNotifier` 에는 왜 인터페이스인지를 주석으로 남긴다 — 실제 발송기는 업체 계약과
사업자등록이 가능해지는 시점에 이 뒤에 붙는다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/services/notification_service_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/repositories/notification_log_repository.dart lib/services/notification_service.dart test/services/notification_service_test.dart
git commit -m "feat: 학부모 알림 서비스와 알림 기록 저장소 추가"
```

---

## Task 10: NetworkInfo + CheckInServer 읽기 엔드포인트 (확인 세션 발급 포함)

> 2026-10-16 개정 반영. 개정 전 본문에는 세션 개념이 없었고 `GET /api/members` 가 무조건
> 공개였다. 스펙은 **명단 조회에도 유효한 토큰을 요구**한다 — 명단이 그냥 열려 있으면
> 연락처 뒷 4자리 확인을 전수 시도할 표적 목록을 그대로 내주는 셈이다.
>
> 흐름: QR 스캔 → `GET /api/session?token=` 으로 토큰을 검증하고 세션을 받는다 →
> 이후 읽기 요청은 세션으로 한다. `POST /api/checkin` 과 체크인 페이지(`GET /checkin`)는
> Task 11·12 에서 붙지만, 라우터는 이번 태스크에서 자리를 잡아둔다.

**Files:**
- Create: `lib/services/network_info.dart`
- Create: `lib/server/checkin_server.dart`
- Test: `test/services/network_info_test.dart`
- Test: `test/server/checkin_server_read_test.dart`

**Interfaces:**
- Consumes: `MemberRepository`, `DeviceBindingRepository` (Task 3),
  `AttendanceService` (Task 7), `QrTokenService`, `VerificationSessionService`,
  `QrKind` (Task 8).
- Produces:
  - `NetworkInfo` 에 `Future<String?> getLocalIPv4()` — 루프백이 아닌 첫 IPv4 주소, 없으면 null
  - `CheckInServer({required MemberRepository memberRepository,
    required DeviceBindingRepository deviceBindingRepository,
    required AttendanceService attendanceService,
    required QrTokenService qrTokenService,
    required VerificationSessionService verificationSessionService})` 에
    `Future<int> start({int port = 8080})` (실제로 바인딩된 포트를 돌려준다),
    `Future<void> stop()`
  - 이번 태스크가 추가하는 라우트:
    - `GET /api/session?token=<qr토큰>` →
      200 `{"sessionId": "...", "kind": "checkIn"|"checkOut"}` / 403 `{"error":"invalid_token"}`
    - `GET /api/members?session=<세션id>` →
      200 `[{"id":1,"name":"홍길동"}]` / 403 `{"error":"invalid_session"}`
    - `GET /api/device-status?deviceToken=<토큰>&session=<세션id>` →
      200 `{"bound":false}` 또는 `{"bound":true,"memberId":1,"memberName":"홍길동"}` /
      403 `{"error":"invalid_session"}`

`shelf_io.serve` 를 `InternetAddress.anyIPv4` 로 띄우고, 테스트는 `port: 0` 으로 임의 포트를
받아 `http` 패키지로 호출한다. 응답 헤더는 모두 `content-type: application/json`.

- [ ] **Step 1: 실패하는 테스트 작성**

`test/services/network_info_test.dart`:

```dart
test('getLocalIPv4 는 null 이거나 점 4개 형식의 IPv4 를 돌려준다', () async {
  final ip = await NetworkInfo().getLocalIPv4();
  if (ip != null) {
    expect(RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(ip), isTrue);
  }
});
```

`test/server/checkin_server_read_test.dart` — 서버 조립은 헬퍼 하나로 묶어 각 테스트가
`startServer(db)` 로 포트를 받게 한다. 테스트 이름과 단정:

```dart
test('GET /api/session 은 등원 토큰에 checkIn 세션을 발급한다', () async {
  // qrTokenService.checkInToken 으로 호출 -> 200, body['kind'] == 'checkIn',
  // body['sessionId'] isNotEmpty
});

test('GET /api/session 은 하원 토큰에 checkOut 세션을 발급한다', () async {
  // body['kind'] == 'checkOut'
});

test('GET /api/session 은 모르는 토큰을 403 으로 거부한다', () async {
  // token=nope -> 403, body['error'] == 'invalid_token'
});

test('GET /api/members 는 세션 없이는 403 이다', () async {
  // session 파라미터 없이 호출 -> 403, body['error'] == 'invalid_session'
});

test('GET /api/members 는 유효한 세션으로 명단을 돌려준다', () async {
  // 회원 '홍길동' 등록 -> /api/session 으로 세션 발급 -> /api/members?session=
  // -> 200, body.single['name'] == '홍길동'
});

test('GET /api/device-status 는 미바인딩 기기와 바인딩된 기기를 구분한다', () async {
  // 'device-1' 을 회원에 bind 한 뒤 유효 세션으로 두 번 호출
  // unknown -> {'bound': false}
  // device-1 -> {'bound': true, 'memberName': '홍길동'}
});

test('GET /api/device-status 는 세션 없이는 403 이다', () async { /* ... */ });
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/services/network_info_test.dart test/server/checkin_server_read_test.dart`
Expected: FAIL — `lib/services/network_info.dart` 와 `lib/server/checkin_server.dart` 가 없다.

- [ ] **Step 3: NetworkInfo 구현**

`NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)` 를 돌며
루프백이 아닌 첫 주소를 돌려준다. 없으면 null.

- [ ] **Step 4: CheckInServer 구현**

위 Interfaces 대로 만든다. 라우터는 `Router()` 에 세 라우트를 등록하고, 세션 검증은
핸들러들이 공유하는 비공개 헬퍼 하나로 뽑는다 — `session` 질의 파라미터를
`verificationSessionService.kindOf` 로 확인해 null 이면 403 을 돌려주는 모양.
`GET /api/session` 은 `qrTokenService.kindOf(token)` 가 null 이면 403, 아니면
`verificationSessionService.issue(kind)` 로 세션을 발급해 돌려준다.

`POST /api/checkin` 과 `GET /checkin` 은 이번 태스크에서 등록하지 않는다 (Task 11·12).

- [ ] **Step 5: 통과 확인**

Run: `flutter test test/services/network_info_test.dart test/server/checkin_server_read_test.dart`
Expected: PASS (8 tests)

- [ ] **Step 6: 전체 테스트 확인**

Run: `flutter test`
Expected: PASS — Task 5~10 까지의 모든 테스트가 녹색이어야 한다.

- [ ] **Step 7: 커밋**

```bash
git add lib/services/network_info.dart lib/server/checkin_server.dart test/services/network_info_test.dart test/server/checkin_server_read_test.dart
git commit -m "feat: 확인 세션 발급과 세션 검증을 갖춘 로컬 서버 읽기 엔드포인트 추가"
```

---

## Task 11: CheckInServer check-in endpoint (POST /api/checkin)

**Files:**
- Modify: `lib/server/checkin_server.dart`
- Test: `test/server/checkin_server_checkin_test.dart`

**Interfaces:**
- Consumes: everything from Task 10's `CheckInServer`, plus `AttendanceService.recordCheckIn` (Task 7) and `DeviceBindingRepository.bind` (Task 3).
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

## Task 12: Check-in web page + serving route

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

## Task 13: CheckInAppController (QR rotation + server lifecycle)

**Files:**
- Create: `lib/services/checkin_app_controller.dart`
- Test: `test/services/checkin_app_controller_test.dart`

**Interfaces:**
- Consumes: `CheckInServer` (Tasks 8-10), `QrTokenService` (Task 8), `NetworkInfo` (Task 10).
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

## Task 14: Admin UI — Member management screen

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

## Task 15: Admin UI — Class management screen

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

## Task 16: Admin UI — Live dashboard (QR + today's check-ins)

**Files:**
- Create: `lib/ui/screens/dashboard_screen.dart`
- Test: `test/ui/dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `CheckInAppController` (Task 13), `AttendanceRepository`, `MemberRepository` (Tasks 3, 5).
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

## Task 17: Admin UI — Attendance history screen

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

## Task 18: App shell wiring (main.dart, navigation, daily absence scheduler)

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
