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

2026-10-16 스펙 개정(등원/하원 QR 분리, 최초 본인 확인 강화, 세션 귀속 규칙)을 반영해
Task 5–14 의 본문을 다시 썼고 **Task 15 까지 구현을 마쳤다** (2026-10-17).
Task 15 는 본문 개정 없이 구현했으나 정정 8건이 필요했다 — 해당 절의 머리말을 볼 것.

| 태스크 | 상태 |
|---|---|
| 1–4 | 완료 |
| **5–10** | **구현 완료** (`3f237a2..97cf63d`, 테스트 77개). 전체 검토 1회 + 수정 패스 완료 |
| **11–13** | **구현 완료** (`7032595..85c2e4e`, 테스트 124개). 태스크별 검토 + 수정 라운드 완료 |
| **14** | **구현 완료** (`b5b940d`, `a3fc77e`, `700f659`, 테스트 147개). 검토 + 수정 라운드 완료 |
| **15** | **구현 완료** (`b912ff8`, `4d4b641`, `5e8eb87`, 테스트 160개). 본문 정정 8건 반영 — **본문의 Step 1·3 코드는 폐기**, 실제 결과물을 볼 것 |
| **16** | **구현 완료** (`77338bd`, `6af5ddf`, `31e116c`, `fe5acbf`, `baf61fd`). **본문 Step 1·3 코드는 폐기** — 해당 절 머리말을 볼 것. 미하원 정의를 스펙대로 바로잡았다 |
| **17** | **구현 완료** (`204d301`, `9e3a4db`, 테스트 193개). **본문 Step 1·3 코드는 폐기** — 해당 절 머리말을 볼 것. 보정 기능을 새로 넣었다 |
| **18** | **구현 완료 + 검증 완료** (`65f6853..62ce17c`, 수정 `f495419`, 테스트 222개). **본문 Step 1·3·5 코드는 폐기** — 해당 절 머리말을 볼 것 |

**전체 자동 테스트 222개 통과, `flutter analyze` 0건** (2026-10-27, Windows 에서 실행).
Task 18 은 Flutter 가 없는 환경에서 작성되어 빨간 상태로 들어왔다. 병합 전 검증에서 컴파일
에러 1건 + 실패 3건 + 린트 3건 + 미적용 포맷 9파일이 나왔고 `f495419` 로 고쳤다. 그중 하나는
프로덕션 결함이었다 — 종료 시 진행 중인 비동기 조회 밑에서 DB 를 닫고 있었다.
**이후 작업도 반드시 Windows 에서 `flutter test` 와 `flutter analyze` 를 돌려 확인할 것.**

> **남은 UI 태스크(15·16·17)가 쓸 위젯 테스트 패턴** — Task 14 가 이 프로젝트의 첫 위젯
> 테스트였고, 두 가지가 섞여 있어 한 번 호되게 걸렸다. 같은 함정을 다시 밟지 말 것.
>
> 1. 위젯 테스트는 가짜 비동기 영역에서 돌기 때문에 `initState` 의 실제 DB 호출이 맨
>    `pumpAndSettle()` 로는 끝나지 않는다. `tester.runAsync` 로 실제 비동기를 흘려야 한다.
> 2. 반대로 다이얼로그 닫힘 같은 라우트 애니메이션은 **가짜 시간**으로만 진행된다.
>    `runAsync` 만 반복해도 영원히 안 닫히고, `pump(Duration.zero)` 로도 안 된다.
>
> 그래서 **real-async 흘리기와 한 프레임 pump 를 번갈아 하면서 조건이 참이면 즉시 빠져나오는**
> 헬퍼가 필요하다. `test/ui/member_management_screen_test.dart` 의 `pumpUntil` 을 그대로 쓸 것.
> 고정 시간 대기(`runAsync(delayed(300ms))` 류)로 때우면 통과하기는 하지만, 느린 머신에서
> 깨지고 "얼마면 충분한가"를 영원히 추측하게 된다.
>
> 단정(assertion)도 범위를 좁혀 걸 것. `find.text` 는 `Text` 뿐 아니라 `EditableText` 도
> 잡으므로, 저장이 실패해 다이얼로그가 열린 채여도 입력칸이 걸려 테스트가 통과한다. 목록을
> 확인하는 단정은 `find.descendant(of: find.byType(ListTile), ...)` 로 행 안에 한정하고,
> 저장 뒤에는 다이얼로그가 닫혔는지(`find.byType(AlertDialog)` 가 없는지)까지 본다.
> Task 14 에서 이 두 개를 놓친 테스트 2개가 **저장이 아예 안 되는 변이에서도 통과**했다.

> ⚠️ **16–18 의 본문은 아직 개정 전 설계를 서술한다.** 그대로 구현하면 하원 현황·보정 기능이
> 빠진 결과물이 나온다. 각 태스크를 시작하기 전에 본문을 먼저 개정할 것.
> 스펙과 충돌하면 스펙이 이긴다 (`2026-09-18-checkin-app-design.md`).

### Task 5–10 에서 이월된 사항

구현과 전체 검토에서 나왔으나 그 범위에서 고치지 않은 것들. **Task 11–14 본문에는 이미
반영했다** — 아래는 어디서 처리되는지의 색인이다.

- **Task 13 에 반영됨**: `QrTokenService.validityDuration` 을 아무도 읽지 않아 현재 토큰이
  영구 유효하다. 회전 타이머가 죽으면(핫 리로드, 콜백 예외) 촬영한 QR 이 계속 통하므로
  "코드가 계속 바뀐다"는 보증이 조용히 사라진다. 또 `CheckInServer.start` 가 재진입을 막지
  않아 두 번 부르면 첫 리스너가 샌다.
- **Task 14 에서 처리됨**: 회원을 삭제해도 `device_bindings` 가 남는 문제는
  `MemberRepository.delete` 가 한 트랜잭션에서 함께 지우도록 고쳤다 (`binding_logs` 는
  사칭 점검용 append-only 기록이라 남긴다). 연락처를 지울 수 없던 문제는 양식이
  `Member` 를 전체 생성하는 쪽으로 해결했다 — 아래 `copyWith` 항목을 볼 것.
- **Task 11 에 반영됨**: JSON 응답에 `cache-control` 이 없다. 모바일 브라우저가
  `/api/device-status` 나 `/api/members` 를 캐시하면 낡은 명단·바인딩 상태를 보여줄 수 있다.
  확인 세션 id 가 질의 문자열로 다니므로 폰 기록에 남는 점도 감안할 것.
- **Task 16·17 에서 처리됨 (지시는 철회)**: `Attendance` 에 `copyWith` 가 없어
  `AttendanceRepository.update` 호출자가 필드를 빠뜨리면 조용히 null 이 되는 위험.
  **`copyWith` 를 추가하라던 원래 지시는 철회했다** — Task 17 절 머리말에 이유가 있다.
  보정 양식이 기존 행에서 출발해 `Attendance` 를 전체 생성하므로 이 위험은 사라졌다.

  > ⚠️ **다만 `copyWith` 를 그냥 추가하면 Task 14 가 겪은 막다른 길을 반복한다.**
  > nullable 필드를 `값 ?? this.값` 으로 합치는 `copyWith` 는 **값을 지우는 수정을 표현할 수
  > 없다** — `null` 을 넘기는 것이 "바꾸지 않음"과 구별되지 않기 때문이다. Task 14 는 이걸
  > `clearParentContact` 플래그로 때우려 했으나, 같은 양식이 `classId` 도 "반 없음"으로
  > 되돌려야 해서 플래그를 필드마다 늘리는 길이 되었다. 결국 양식이 `Member` 를 **전체
  > 생성**하는 쪽으로 갔고, `clearParentContact` 는 프로덕션 호출자를 잃어 지금은 자기
  > 단위 테스트만 쓰고 있다 (최종 브랜치 검토에서 제거 여부를 결정할 것).
  >
  > 출결 보정은 **하원 시각을 지워야 하는 수정이 실제로 생기는** 화면이다 (잘못 찍힌 하원을
  > 되돌리기). 그러니 `Attendance` 에서는 처음부터 전체 생성이나 명시적 "지움" 표현을 쓰고,
  > `clear...` 플래그를 필드마다 붙이는 길로 가지 말 것. 어느 쪽을 택하든 **하원 시각을
  > null 로 되돌리는 보정**이 테스트로 증명되어야 한다.

- **Task 15 에서 처리됨** (Task 14 에서 드러남): `ClassRepository.delete` 가
  `members.class_id` 를 정리하지 않아, 반을 삭제하면 존재하지 않는 반을 가리키는 회원이
  남았다. 그 회원의 수정 다이얼로그는 `DropdownButton` 의 "value 와 같은 item 이 정확히
  1개여야 한다" assert 로 깨졌다 — 즉 **그 회원을 수정할 수 없었다.** 이제 반 삭제가 한
  트랜잭션에서 `UPDATE members SET class_id = NULL` 을 먼저 한다 (회원은 지우지 않는다).
  Task 14 의 양식 쪽 정규화도 그대로 남겨 두었다 — 이중 방어다.
  `PRAGMA foreign_keys` 는 여전히 켜지 않는다 (기존 테스트 다수가 존재하지 않는 `member_id`
  로 바인딩·출결을 넣고 있어 한꺼번에 깨진다).
- **Task 18 에서 처리할 것** (아직 본문 미개정): `DatabaseHelper` 는 아직 `version: 1` 에
  `onUpgrade` 가 없다. 지금은 파일 DB 를 여는 곳이 없어 안전하지만, 앱 셸이 실제 경로를
  붙이는 순간 Task 5 이전 체크아웃의 DB 파일을 가진 사람은 `no such column: parent_contact`
  를 런타임에 만난다. 버전을 올리고 `onUpgrade` 를 붙일 것.

- **Task 18 에서 확인할 것 — DB 파일 경로의 비ASCII 문자**: 지금 테스트는 전부
  `inMemoryDatabasePath` 를 쓰고 앱이 실제 파일을 여는 곳이 아직 없다. Task 18 이 진짜 경로를
  붙일 때, 그 경로에 한글이 섞이면(사용자 폴더나 설치 위치에 따라 생길 수 있다)
  `sqflite_common_ffi` 가 Windows 에서 열지 못할 수 있다. **실제 경로를 붙인 직후 한글이 든
  폴더에서 한 번 열어 보고 넘어갈 것.** 현재 개발 환경 자체는 깨끗하다 — 프로젝트 경로,
  Flutter SDK 경로, pub 캐시 경로, `.dart_tool/package_config.json` 전부 ASCII 이고 옛 경로
  잔재도 없다 (2026-10-17 확인).

- **테스트 출력의 `sqflite warning` 노이즈** (범위 밖, 아무 때나 해도 됨):
  `test/helpers/test_db.dart` 의 `openTestDatabase()` 가 호출마다 `databaseFactory` 를 다시
  세팅해서 `You are changing sqflite default factory` 경고가 DB 를 여는 횟수만큼 찍힌다
  (160개 테스트 기준 수백 줄). 기능 영향은 없고 전부 통과한다. 초기화를 한 번만 하도록
  플래그를 두면 사라진다. 실패를 눈으로 찾기 어려워질 때 정리할 것.
- **Task 18 (결석 스케줄러)**: `markAbsentees` 는 현재 날짜에 돌려도 안전하다 — 결석 행이
  먼저 들어와도 그 뒤의 등원 스캔이 그 행을 등원으로 올린다(`fillCheckIn`). 다만 스펙은
  "하루 종료 시점"을 정하고 있으므로 그대로 따를 것.

---

## Review Focus

실행 범위의 태스크 테스트가 직접 다루지 않으면서, 쓰는 사람을 물 가능성이 높은 입력·상황들.
각 줄의 테스트는 그 코드를 소유한 태스크에 넣어둔다.

### Task 11–15 (현재 범위)

- **재스캔으로 학부모 알림이 두 번 가는 것** — 등원·하원을 다시 찍어도 알림은 한 번만 나가야
  한다. `recorded` 일 때만 알림을 내는 규칙이 엔드포인트에서 실제로 지켜지는지 (Task 11).
- **뒷 4자리 전수 시도** — 로컬 네트워크에서 스크립트로 1만 조합을 돌릴 수 있다. 5회 실패
  뒤에는 올바른 4자리를 보내도 잠겨 있어야 한다 (Task 11).
- **연락처가 저장 형식에 따라 갈리는 것** — `'010-1111-2222'` 와 `'01011112222'` 가 같은
  뒷 4자리로 판정되어야 한다. 숫자만 남겨 비교한다 (Task 11).
- **인터넷 없는 네트워크에서 열리는 페이지** — 체크인 페이지가 CDN 스크립트·폰트를 참조하면
  학원 WiFi(WAN 끊김 포함)에서 그 자리에서 깨진다. 외부 리소스를 참조하지 않아야 한다
  (Task 12).
- **빈 문자열 연락처** — 회원 양식에서 연락처를 비워두면 `null` 로 저장되어야 한다. 빈
  문자열이 들어가면 뒷 4자리 확인이 빈 값과 비교되어 아무 입력으로도 통과한다 (Task 14).

### Task 5–10 (완료 — 전체 검토에서 전부 확인됨)

- **자정을 넘긴 하원** — 23:50 등원 후 00:20 하원. 등원한 날짜의 행에 들어가야 하고, 다음 날
  행이 새로 생기거나 등원 없는 하원으로 기록되어서는 안 된다 (Task 6·7).
- **열린 세션이 둘인 상태의 하원** — 어제 안 닫힌 세션 + 오늘 등원. 오래된 쪽을 닫으면 어제
  방문에 엉뚱한 하원 시각이 붙고 거짓 알림까지 나간다. 최근 쪽을 닫아야 한다 (Task 6·7).
- **등원 없이 하원 QR 만 스캔** — 저녁 시각의 등원(지각)으로 잘못 기록되지 않고
  `noOpenSession` 으로 거부되어야 한다 (Task 7).
- **등원 QR 재스캔** — 하원으로 넘어가지 않고 기록도 바뀌지 않아야 한다. 2026-10-16 개정의
  존재 이유가 이 입력이다 (Task 7).
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

## Task 11: CheckInServer 쓰기 엔드포인트 (기기 바인딩 + 등원/하원 기록)

> 2026-10-16 개정으로 전면 재작성. 개정 전 본문은 `POST /api/checkin` 하나가 QR 토큰을 직접
> 받아 등원만 기록했고, 본인 확인·확인 세션·하원·알림이 모두 없었다.
>
> 이번 태스크가 붙이는 것은 두 개다. **바인딩**(`POST /api/bind`)은 처음 온 폰을 회원에
> 묶으며 학부모 연락처 뒷 4자리로 본인을 확인한다. **체크**(`POST /api/checkin`)는 묶인 폰의
> 등원 또는 하원을 기록하고, 새로 기록된 경우에만 학부모 알림을 낸다.
>
> 둘 다 QR 토큰이 아니라 **확인 세션**을 받는다 (Task 10). 어느 QR 을 스캔했는지는 세션에
> 담긴 `QrKind` 가 말해주므로, 클라이언트가 등원/하원을 고르지 않는다 — 고를 수 있으면
> 등원 QR 로 하원을 위조할 수 있다.

**Files:**
- Create: `lib/services/bind_attempt_throttle.dart`
- Modify: `lib/server/checkin_server.dart`
- Test: `test/services/bind_attempt_throttle_test.dart`
- Test: `test/server/checkin_server_write_test.dart`

**Interfaces:**
- Consumes: Task 10 의 `CheckInServer`, `AttendanceService` 와 그 결과 타입
  (`CheckInStatus`, `CheckOutStatus`) (Task 7), `NotificationService` (Task 9),
  `DeviceBindingRepository.bind` (Task 5), `VerificationSessionService`, `QrKind` (Task 8).
- Produces:
  - `BindAttemptThrottle({int maxAttempts = 5, Duration lockout = const Duration(minutes: 10)})` 에
    - `bool isLocked(String deviceToken, {DateTime? now})`
    - `void recordFailure(String deviceToken, {DateTime? now})` — `maxAttempts` 번째 실패에서 잠근다
    - `void clear(String deviceToken)` — 성공 시 실패 횟수를 지운다
  - `CheckInServer` 생성자에 두 개 추가: `required NotificationService notificationService`,
    `required BindAttemptThrottle bindAttemptThrottle`
  - `POST /api/bind` — body `{session, deviceToken, memberId, contactLast4}`
    | 상황 | 응답 |
    |---|---|
    | 성공 | 200 `{"bound":true,"memberName":"홍길동"}` |
    | 세션 무효 | 403 `{"error":"invalid_session"}` |
    | 회원 없음 | 400 `{"error":"unknown_member"}` |
    | 회원에 학부모 연락처가 없음 | 403 `{"error":"verification_unavailable"}` |
    | 뒷 4자리 불일치 | 403 `{"error":"verification_failed"}` |
    | 연속 실패 5회 뒤 | 429 `{"error":"too_many_attempts"}` |
  - `POST /api/checkin` — body `{session, deviceToken}`. 등원/하원은 세션의 `QrKind` 가 정한다.
    | 상황 | 응답 |
    |---|---|
    | 등원 기록됨 | 200 `{"result":"checkedIn","memberName":"홍길동","status":"present"}` |
    | 이미 등원함 | 200 `{"result":"alreadyCheckedIn","memberName":"홍길동"}` |
    | 하원 기록됨 | 200 `{"result":"checkedOut","memberName":"홍길동"}` |
    | 이미 하원함 | 200 `{"result":"alreadyCheckedOut","memberName":"홍길동"}` |
    | 하원인데 열린 세션 없음 | 400 `{"error":"no_open_session"}` |
    | 기기가 묶이지 않음 | 400 `{"error":"member_required"}` |
    | 세션 무효 | 403 `{"error":"invalid_session"}` |

**알림 규칙 (스펙):** `notificationService.onCheckIn` / `onCheckOut` 은 결과가 `recorded` 일
때만 부른다. `alreadyCheckedIn`·`alreadyCheckedOut`·`no_open_session` 에서는 부르지 않는다 —
재스캔마다 학부모에게 알림이 가면 안 된다.

**세션 소비:** 두 엔드포인트 모두 성공했을 때 `verificationSessionService.consume(session)` 을
부른다. 바인딩 성공 뒤 같은 세션으로 체크까지 할 수 있어야 하므로, **바인딩은 소비하지 않고**
체크만 소비한다.

- [ ] **Step 1: `BindAttemptThrottle` 의 실패하는 테스트 작성**

`test/services/bind_attempt_throttle_test.dart`:

```dart
test('실패가 maxAttempts 에 닿으면 잠긴다', () {
  final throttle = BindAttemptThrottle(maxAttempts: 5);
  final at = DateTime(2026, 10, 16, 15, 0);
  for (var i = 0; i < 4; i++) {
    throttle.recordFailure('device-1', now: at);
  }
  expect(throttle.isLocked('device-1', now: at), isFalse);
  throttle.recordFailure('device-1', now: at);
  expect(throttle.isLocked('device-1', now: at), isTrue);
});

test('lockout 이 지나면 다시 풀린다', () {
  // 5회 실패 후 at+9분 -> 잠김, at+11분 -> 풀림 (lockout 10분)
});

test('clear 는 실패 횟수를 지운다', () {
  // 4회 실패 -> clear -> 다시 4회 실패해도 잠기지 않는다
});

test('기기별로 따로 센다', () {
  // device-1 을 5회 실패시켜도 device-2 는 잠기지 않는다
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/services/bind_attempt_throttle_test.dart`
Expected: FAIL — `lib/services/bind_attempt_throttle.dart` 가 없다.

- [ ] **Step 3: `BindAttemptThrottle` 구현**

기기 토큰 → (연속 실패 횟수, 마지막 실패 시각) 맵. `isLocked` 는 횟수가 `maxAttempts` 이상이고
마지막 실패로부터 `lockout` 이 지나지 않았을 때 true. `lockout` 이 지났으면 그 항목을 지우고
false. `VerificationSessionService` 와 같은 이유로 `recordFailure` 에서 만료된 항목을 치운다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/services/bind_attempt_throttle_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: 커밋**

이 태스크는 커밋을 두 번 한다. 차단 장치와 두 엔드포인트는 각각 독립적으로 검토될 수 있는
단위이므로, 여기서 한 번 끊어 TDD 사이클을 짧게 유지한다.

```bash
git add lib/services/bind_attempt_throttle.dart test/services/bind_attempt_throttle_test.dart
git commit -m "feat: 기기 바인딩 실패 차단 장치 추가"
```

- [ ] **Step 6: 서버 쓰기 엔드포인트의 실패하는 테스트 작성**

`test/server/checkin_server_write_test.dart`. Task 10 의 `checkin_server_read_test.dart` 가 쓰는
것과 같은 모양의 `_Harness` 를 두되, `notificationService` 와 `bindAttemptThrottle`,
그리고 알림 확인용 `NotificationLogRepository` 를 함께 노출한다. 테스트 이름과 단정:

```dart
test('POST /api/bind 는 뒷 4자리가 맞으면 기기를 묶는다', () async {
  // parentContact '010-1111-2222' 인 회원, contactLast4 '2222'
  // -> 200, body['memberName'], getByToken('device-1').memberId == memberId
});

test('POST /api/bind 는 뒷 4자리가 틀리면 403 verification_failed 이고 묶지 않는다', () async {
  // contactLast4 '9999' -> 403, getByToken('device-1') isNull
});

test('POST /api/bind 는 연락처가 없는 회원을 403 verification_unavailable 로 거부한다', () async {
  // parentContact 없는 회원 -> 403, 관리자 대행이 필요하다는 뜻
});

test('POST /api/bind 는 연락처의 하이픈 유무와 무관하게 뒷 4자리를 판정한다', () async {
  // parentContact '01011112222' (하이픈 없음) 인 회원에 contactLast4 '2222' -> 200
  // 저장 형식이 갈려도 같게 동작해야 한다 — 관리자가 어느 형식으로 입력했는지에 따라
  // 학생이 바인딩에 실패하면 원인을 알 길이 없다
});

test('POST /api/bind 는 연속 5회 실패 뒤 429 를 돌려준다', () async {
  // 틀린 4자리로 5번 -> 6번째는 429 too_many_attempts
  // (올바른 4자리를 보내도 잠긴 동안에는 429)
});

test('POST /api/bind 는 세션 없이는 403 이다', () async { /* invalid_session */ });

test('POST /api/checkin 은 등원 세션으로 등원을 기록하고 알림을 낸다', () async {
  // 묶인 기기 + 등원 QR 세션 -> 200 result 'checkedIn', status 'present'
  // notificationLogRepo.getRecent() 가 1건, kind checkIn
});

test('POST /api/checkin 재스캔은 alreadyCheckedIn 이고 알림을 더 내지 않는다', () async {
  // 두 번 호출 -> 두 번째 result 'alreadyCheckedIn', 알림 로그는 여전히 1건
});

test('POST /api/checkin 은 하원 세션으로 하원을 기록하고 알림을 낸다', () async {
  // 등원 뒤 하원 QR 세션 -> 200 result 'checkedOut', 알림 2건(checkIn, checkOut)
});

test('POST /api/checkin 은 등원 없이 하원하면 400 no_open_session 이고 알림을 내지 않는다', () async {
  // 하원 QR 세션만 -> 400, 알림 로그 비어 있음
});

test('POST /api/checkin 은 묶이지 않은 기기를 400 member_required 로 거부한다', () async { /* ... */ });

test('POST /api/checkin 은 세션 없이는 403 이다', () async { /* invalid_session */ });

test('체크에 쓴 세션은 소비되어 재사용할 수 없다', () async {
  // 등원 성공 뒤 같은 세션으로 다시 POST -> 403 invalid_session
});
```

- [ ] **Step 7: 실패 확인**

Run: `flutter test test/server/checkin_server_write_test.dart`
Expected: FAIL — 두 라우트가 없어 404, 그리고 `CheckInServer` 생성자가 새 인자 2개를 모른다.

- [ ] **Step 8: 두 엔드포인트 구현**

`lib/server/checkin_server.dart` 에 `router.post('/api/bind', ...)` 와
`router.post('/api/checkin', ...)` 를 등록한다. 세션 검증은 Task 10 의
`_rejectUnlessSession` 을 쓰되, 본문(JSON) 에서 `session` 을 읽어야 하므로 body 를 받는
형태가 하나 더 필요하다 — 질의 파라미터용과 본문용으로 갈라 두고 둘이 같은 판정을 쓰게 한다.

뒷 4자리 비교는 저장된 연락처에서 **숫자만 남겨** 마지막 4자를 취해 비교한다
(`'010-1111-2222'` → `'2222'`). 저장 형식이 하이픈 유무로 갈려도 같게 동작해야 한다.

`_json` 에 `cache-control: no-store` 를 추가한다 — 모바일 브라우저가 체크 응답이나 명단을
캐시하면 낡은 상태를 보여준다 (Task 5~10 전체 검토의 이월 사항).

- [ ] **Step 9: 통과 확인**

Run: `flutter test test/server/checkin_server_write_test.dart test/server/checkin_server_read_test.dart`
Expected: PASS (13 + 9 tests)

- [ ] **Step 10: 전체 테스트 확인**

Run: `flutter test`
Expected: PASS

- [ ] **Step 11: 커밋**

```bash
git add lib/services/bind_attempt_throttle.dart lib/server/checkin_server.dart test/services/bind_attempt_throttle_test.dart test/server/checkin_server_write_test.dart
git commit -m "feat: 본인 확인 바인딩과 등원·하원 기록 엔드포인트 추가"
```

---

## Task 12: 체크인 웹페이지 + 서빙 라우트

> 2026-10-16 개정 반영. 개정 전 본문은 등원만 있는 한 장짜리 페이지였다. 이제 페이지는
> 스캔한 QR 의 종류(등원/하원)에 따라 다르게 동작하고, 최초 1회는 본인 확인을 거친다.
>
> **테스트할 수 있는 것과 없는 것을 구분한다.** 이 프로젝트에 브라우저 자동화가 없으므로
> 페이지 안의 JS 동작은 테스트하지 않는다. 테스트는 라우트가 HTML 을 올바른 타입으로
> 서빙하는지와, 페이지가 Task 11·10 이 정한 엔드포인트와 결과 코드를 실제로 참조하는지까지다.
> 후자는 사소해 보이지만, 엔드포인트 이름이 바뀌었는데 페이지만 옛 이름을 들고 있는 상황을
> 잡아준다 — 그 조합은 수동으로 열어보지 않으면 드러나지 않는다.

**Files:**
- Create: `lib/server/checkin_page.dart`
- Modify: `lib/server/checkin_server.dart`
- Test: `test/server/checkin_page_route_test.dart`

**Interfaces:**
- Consumes: Task 10·11 의 `CheckInServer` 와 그 엔드포인트·결과 코드.
- Produces: `const String checkInPageHtml` — 외부 의존이 없는 자체 완결 HTML+JS 한 장.
  `GET /checkin` 이 `content-type: text/html; charset=utf-8` 로 서빙한다.

**페이지가 하는 일** (구현 지침이며, 각 줄이 HTML 안에 그대로 나타나야 한다):

1. URL 의 `?token=` 을 읽어 `GET /api/session?token=` 을 부른다. 403 이면
   "QR 코드가 만료되었습니다. 다시 스캔해 주세요." 를 보여주고 끝낸다.
2. 받은 `sessionId` 와 `kind` 를 기억한다. 화면 제목을 `kind` 에 따라 "등원" 또는 "하원"으로
   둔다 — 학생이 무엇을 찍었는지 화면에서 확인할 수 있어야 한다.
3. `localStorage` 의 `deviceToken` 을 읽는다. 없으면 `crypto.getRandomValues` 로 16자 hex 를
   만들어 저장한다.
4. `GET /api/device-status?deviceToken=&session=` 을 부른다.
   - `bound: true` → 곧바로 5번으로 간다.
   - `bound: false` → `GET /api/members?session=` 으로 명단을 받아 이름 목록을 보여주고,
     고른 뒤 학부모 연락처 뒷 4자리를 입력받아 `POST /api/bind` 를 부른다.
     `verification_unavailable` 이면 "관리자에게 요청해 주세요." 를,
     `verification_failed` 면 "연락처가 일치하지 않습니다." 를,
     `too_many_attempts` 면 "잠시 후 다시 시도해 주세요." 를 보여준다.
5. `POST /api/checkin` 을 부르고 결과를 그린다.
   - `checkedIn` → "{이름} 님 등원 완료" + `status` 가 `late` 면 "지각" 표시
   - `checkedOut` → "{이름} 님 하원 완료"
   - `alreadyCheckedIn` → "이미 등원하셨습니다"
   - `alreadyCheckedOut` → "오늘은 이미 하원 처리되었습니다"
   - `no_open_session` → "등원 기록이 없습니다"
6. 하단에 "다른 사람으로 체크" 버튼을 둔다. 누르면 `localStorage` 의 `deviceToken` 을 지우고
   4번의 본인 확인을 다시 거친다 (폰을 여러 명이 쓰는 경우).

- [ ] **Step 1: 실패하는 테스트 작성**

`test/server/checkin_page_route_test.dart`. Task 11 의 `_Harness` 와 같은 조립을 쓴다.

```dart
test('GET /checkin 은 체크인 HTML 을 서빙한다', () async {
  // 200, content-type 에 'text/html', body 에 '<!doctype html' (대소문자 무시)
});

test('페이지는 서버가 실제로 가진 엔드포인트만 참조한다', () async {
  // checkInPageHtml 에 '/api/session', '/api/device-status', '/api/members',
  // '/api/bind', '/api/checkin' 이 모두 들어 있다
});

test('페이지는 Task 11 의 결과 코드를 모두 다룬다', () async {
  // checkInPageHtml 에 'checkedIn', 'checkedOut', 'alreadyCheckedIn',
  // 'alreadyCheckedOut', 'no_open_session',
  // 'verification_failed', 'verification_unavailable', 'too_many_attempts' 가 들어 있다
});

test('페이지는 기기 토큰을 localStorage 에 둔다', () async {
  // checkInPageHtml 에 'localStorage' 와 'deviceToken' 이 들어 있다
});

test('페이지는 외부 스크립트·스타일을 불러오지 않는다', () async {
  // 체크인 페이지는 인터넷이 없는 로컬 네트워크에서 열린다 — CDN 을 참조하면 그 자리에서
  // 깨진다. body 에 'http://' 와 'https://' 가 없어야 한다 (로컬 상대 경로만 쓴다)
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/server/checkin_page_route_test.dart`
Expected: FAIL — `lib/server/checkin_page.dart` 가 없고 `GET /checkin` 라우트도 없다.

- [ ] **Step 3: 페이지 구현**

`lib/server/checkin_page.dart` 에 `const String checkInPageHtml` 로 위 1~6 을 수행하는 한 장을
만든다. `<meta name="viewport" content="width=device-width, initial-scale=1">` 를 넣는다 —
학생 폰에서 열린다. 외부 리소스를 참조하지 않는다.

- [ ] **Step 4: 라우트 추가**

`CheckInServer._router` 에 `router.get('/checkin', ...)` 를 등록하고
`content-type: text/html; charset=utf-8` 로 돌려준다.

- [ ] **Step 5: 통과 확인**

Run: `flutter test test/server/checkin_page_route_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 6: 커밋**

```bash
git add lib/server/checkin_page.dart lib/server/checkin_server.dart test/server/checkin_page_route_test.dart
git commit -m "feat: 등원·하원과 본인 확인을 다루는 체크인 페이지 추가"
```

---

## Task 13: CheckInAppController (QR 2종 회전 + 서버 수명)

> 2026-10-16 개정 반영. 개정 전 본문은 QR 하나(`qrUrl`)만 들고 있었다. 카운터 화면에 등원용과
> 하원용이 나란히 떠야 하므로 URL 도 두 개가 된다.
>
> Task 5~10 전체 검토의 이월 사항 두 개를 여기서 처리한다: `start` 재진입 방지와,
> 회전 타이머가 멈췄을 때 현재 토큰이 영구 유효해지는 문제.

**Files:**
- Create: `lib/services/checkin_app_controller.dart`
- Modify: `lib/services/qr_token_service.dart` (현재 토큰에도 수명을 적용)
- Modify: `lib/server/checkin_server.dart` (`start` 재진입 방지)
- Test: `test/services/checkin_app_controller_test.dart`
- Test: `test/services/qr_token_service_test.dart` (수명 테스트 추가)
- Test: `test/server/checkin_server_read_test.dart` (재진입 테스트 추가)

**Interfaces:**
- Consumes: `CheckInServer` (Task 10·11·12), `QrTokenService` (Task 8),
  `NetworkInfo` (Task 10).
- Produces: `CheckInAppController({required QrTokenService qrTokenService,
  required CheckInServer server, required NetworkInfo networkInfo, int port = 8080,
  Duration rotationInterval = const Duration(seconds: 30)})` 에
  - `ValueNotifier<String?> checkInUrl` — 등원용 QR 에 담을 주소. 서버가 뜨기 전이면 null
  - `ValueNotifier<String?> checkOutUrl` — 하원용
  - `Future<void> start()` — 서버를 띄우고 주소를 채우고 회전 타이머를 건다
  - `Future<void> rotateNow()` — 즉시 두 토큰을 돌리고 두 주소를 갱신한다
  - `Future<void> stop()` — 타이머를 끊고 서버를 내린다
  - `void dispose()`

주소 형식: `http://<로컬IPv4>:<실제포트>/checkin?token=<해당 종류의 토큰>`.
`NetworkInfo.getLocalIPv4()` 가 null 이면 두 `ValueNotifier` 는 null 로 둔다 — 주소를 만들 수
없다는 뜻이고, 화면은 "네트워크를 찾을 수 없습니다"를 보여줄 근거로 쓴다.

**`QrTokenService` 변경:** `kindOf` 가 현재 토큰도 거부해야 한다 —
`_rotatedAt != null && now >= _rotatedAt + validityDuration + graceDuration` 이면 null.
지금은 `validityDuration` 을 아무도 읽지 않아, 회전 타이머가 죽으면(핫 리로드, 콜백 예외)
촬영한 QR 이 영구히 통한다. "코드가 계속 바뀐다"는 스펙의 보증이 외부 타이머 하나에만
걸려 있어서는 안 된다.

- [ ] **Step 1: 실패하는 테스트 작성**

`test/services/qr_token_service_test.dart` 에 추가:

```dart
test('회전이 멈추면 현재 토큰도 수명이 지나면 거부된다', () {
  final service = QrTokenService(
    validityDuration: const Duration(seconds: 30),
    graceDuration: const Duration(seconds: 10),
  );
  final rotatedAt = DateTime(2026, 10, 16, 12, 0, 0);
  service.rotate(now: rotatedAt);
  final token = service.checkInToken;

  expect(service.kindOf(token, now: rotatedAt.add(const Duration(seconds: 39))), QrKind.checkIn);
  expect(service.kindOf(token, now: rotatedAt.add(const Duration(seconds: 41))), isNull);
});
```

`test/server/checkin_server_read_test.dart` 에 추가:

```dart
test('start 를 두 번 불러도 같은 포트를 돌려주고 리스너가 새지 않는다', () async {
  // 이미 뜬 서버에 start(port: 0) 를 다시 불러도 첫 포트와 같고, stop 한 뒤 접속이 끊긴다
});
```

`test/services/checkin_app_controller_test.dart` 생성. `NetworkInfo` 를 고정값으로 대체하는
작은 구현체(`_FixedNetworkInfo`, `_NoNetworkInfo`)를 둔다:

```dart
test('start 는 두 종류의 주소를 각자의 토큰으로 채운다', () async {
  // checkInUrl 과 checkOutUrl 이 모두 'http://192.168.1.50:<port>/checkin?token=' 로 시작하고,
  // 두 주소의 token 값이 서로 다르며 각각 qrTokenService 의 checkIn/checkOut 토큰과 같다
});

test('rotateNow 는 두 주소를 모두 바꾼다', () async {
  // 이전 두 주소를 기억하고 rotateNow 뒤 둘 다 달라진다
});

test('로컬 IPv4 를 찾을 수 없으면 두 주소가 null 이다', () async {
  // _NoNetworkInfo -> start 뒤에도 checkInUrl, checkOutUrl 모두 null
});

test('stop 뒤에는 서버에 접속할 수 없다', () async {
  // start -> http.get 성공 -> stop -> http.get 이 예외를 던진다
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/services/qr_token_service_test.dart test/services/checkin_app_controller_test.dart test/server/checkin_server_read_test.dart`
Expected: FAIL — `checkin_app_controller.dart` 가 없고, 현재 토큰 수명과 `start` 재진입
방지가 아직 없다.

- [ ] **Step 3: `QrTokenService` 에 현재 토큰 수명 적용**

위 변경 설명대로 `kindOf` 에 조건을 더한다. `_rotatedAt` 이 null 이면(아직 한 번도 돌지
않았으면) 현재 토큰은 유효하다 — 앱이 막 뜬 상태다.

- [ ] **Step 4: `CheckInServer.start` 재진입 방지**

`_server != null` 이면 새로 띄우지 않고 기존 포트를 돌려준다.

- [ ] **Step 5: `CheckInAppController` 구현**

위 Interfaces 대로 만든다. `start` 는 `server.start(port: port)` 로 실제 포트를 받고,
`networkInfo.getLocalIPv4()` 로 주소를 만들고, `Timer.periodic(rotationInterval)` 로
`rotateNow` 를 건다. `stop` 과 `dispose` 는 타이머를 취소한다.

- [ ] **Step 6: 통과 확인**

Run: `flutter test`
Expected: PASS

- [ ] **Step 7: 커밋**

```bash
git add lib/services/checkin_app_controller.dart lib/services/qr_token_service.dart lib/server/checkin_server.dart test
git commit -m "feat: QR 2종 회전과 서버 수명을 관리하는 컨트롤러 추가"
```

---

## Task 14: 관리자 UI — 회원 관리 화면

> 2026-10-16 개정 반영. 개정 전 본문에는 학부모 연락처 입력이 없었다. 연락처는 알림 수신처일
> 뿐 아니라 **최초 기기 바인딩의 본인 확인 수단**이므로, 비어 있으면 그 회원은 폰을 혼자
> 묶을 수 없고 관리자가 대행해야 한다 — 화면이 그 사실을 보여줘야 한다.
>
> Task 5~10 전체 검토의 이월 사항 두 개를 여기서 처리한다: 회원을 삭제해도 남는
> `device_bindings` 고아 행과, `Member.copyWith` 로 연락처를 지울 수 없는 문제.

**Files:**
- Create: `lib/ui/screens/member_management_screen.dart`
- Modify: `lib/models/member.dart` (`copyWith` 로 연락처를 지울 수 있게)
- Modify: `lib/repositories/member_repository.dart` (삭제 시 바인딩 정리)
- Test: `test/ui/member_management_screen_test.dart`
- Test: `test/models/models_test.dart` (`copyWith` 테스트 추가)
- Test: `test/repositories/member_repository_test.dart` (삭제 정리 테스트 추가)

**Interfaces:**
- Consumes: `MemberRepository`, `ClassRepository` (Task 3·4), `Member`, `ClassModel`.
- Produces:
  - `MemberManagementScreen({required MemberRepository memberRepository,
    required ClassRepository classRepository})` — `StatefulWidget`. 회원 목록에
    이름·소속 반·학부모 연락처를 보여주고 추가·수정·삭제를 할 수 있다. 연락처가 비어 있는
    회원에는 "연락처 없음 — 기기 바인딩은 관리자 대행" 표시를 붙인다.
  - `Member.copyWith` 에 `bool clearParentContact = false` 를 더한다. true 면
    `parentContact` 를 null 로 만든다. (`parentContact: null` 만으로는 "바꾸지 않음"과
    구별되지 않아, 잘못 입력한 연락처를 지울 수 없다.)
  - `MemberRepository.delete(int id)` 가 같은 호출에서 그 회원의 `device_bindings` 행을
    지운다. `binding_logs` 는 **지우지 않는다** — 사칭 점검용 append-only 기록이다.

**결정:** `PRAGMA foreign_keys` 는 켜지 않는다. 켜면 기존 테스트 다수가 존재하지 않는
`member_id` 로 바인딩·출결을 넣고 있어 한꺼번에 깨지고, 정리해야 할 관계는 지금 이 하나뿐이다.
저장소가 직접 정리하는 쪽이 범위가 작다.

- [ ] **Step 1: 모델·저장소의 실패하는 테스트 작성**

`test/models/models_test.dart` 에 추가:

```dart
test('copyWith 는 clearParentContact 로 연락처를 지운다', () {
  const member = Member(id: 1, name: '홍길동', parentContact: '010-0000-0000');
  expect(member.copyWith(clearParentContact: true).parentContact, isNull);
  expect(member.copyWith(name: '김철수').parentContact, '010-0000-0000');
});
```

`test/repositories/member_repository_test.dart` 에 추가:

```dart
test('회원을 지우면 그 기기 바인딩도 지워진다', () async {
  // 회원 등록 -> bind('device-1', id) -> delete(id)
  // -> deviceRepo.getByToken('device-1') isNull
  // -> binding_logs 는 1건 그대로 (사칭 점검 기록은 남는다)
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/models/models_test.dart test/repositories/member_repository_test.dart`
Expected: FAIL — `clearParentContact` 인자가 없고, 삭제가 바인딩을 남긴다.

- [ ] **Step 3: 모델·저장소 구현**

`Member.copyWith` 에 `bool clearParentContact = false` 를 더한다.
`MemberRepository.delete` 에서 `device_bindings` 를 `member_id` 로 먼저 지운 뒤 회원을 지운다.

- [ ] **Step 4: 화면의 실패하는 테스트 작성**

`test/ui/member_management_screen_test.dart`:

```dart
testWidgets('회원을 추가하면 목록에 나온다', (tester) async {
  // FAB 탭 -> 이름 '홍길동' 입력 -> 저장 -> 목록에 '홍길동'
});

testWidgets('학부모 연락처를 입력하면 저장되고 목록에 보인다', (tester) async {
  // 이름 + 연락처 '010-1111-2222' -> 저장 -> 목록에 연락처가 보이고
  // memberRepository.getAll().single.parentContact == '010-1111-2222'
});

testWidgets('연락처가 없는 회원에는 관리자 대행 안내가 붙는다', (tester) async {
  // 연락처 없이 추가 -> 목록에 '관리자 대행' 문구가 보인다
});

testWidgets('연락처를 비워 저장하면 빈 문자열이 아니라 null 이 들어간다', (tester) async {
  // 연락처 칸을 건드리지 않고 저장 -> getAll().single.parentContact isNull
  // 빈 문자열이 저장되면 뒷 4자리 확인이 ''.endsWith('') 류로 통과해, 아무 입력으로도
  // 남의 기기를 묶을 수 있게 된다
});

testWidgets('회원에 반을 지정할 수 있다', (tester) async {
  // 반 '국어반' 이 있는 상태에서 추가 시 반을 고르면 저장된 classId 가 그 반이다
});

testWidgets('회원을 삭제하면 목록에서 사라진다', (tester) async {
  // 추가 -> 삭제 -> 목록에 없고 getAll() 이 비어 있다
});
```

- [ ] **Step 5: 실패 확인**

Run: `flutter test test/ui/member_management_screen_test.dart`
Expected: FAIL — `lib/ui/screens/member_management_screen.dart` 가 없다.

- [ ] **Step 6: 화면 구현**

`StatefulWidget` 으로 만든다. `initState` 에서 회원과 반을 읽어 `setState` 로 그린다.
추가·수정은 `showDialog` 안의 양식(이름, 학부모 연락처, 반 선택)으로 받고, 저장 후 목록을
다시 읽는다. 연락처가 비어 있으면 `null` 로 저장한다 — 빈 문자열을 넣으면 뒷 4자리 확인이
빈 값과 비교되어 통과해버린다.

- [ ] **Step 7: 통과 확인**

Run: `flutter test`
Expected: PASS

- [ ] **Step 8: 커밋**

```bash
git add lib/ui lib/models/member.dart lib/repositories/member_repository.dart test
git commit -m "feat: 학부모 연락처를 다루는 회원 관리 화면 추가"
```

---

## Task 15: Admin UI — Class management screen

> ✅ **구현 완료** (2026-10-17): `b912ff8`, `4d4b641`, `5e8eb87`. 테스트 160개.
>
> **아래 본문의 Step 1·3 코드는 폐기됐다. 베끼지 말 것.** 이 본문은 Task 14 보다 먼저
> 쓰였고, 거기 적힌 위젯 테스트 패턴(`testWidgets` 안에서 `await openTestDatabase()` +
> 맨 `pumpAndSettle()`)은 동작하지 않는다. 실제로 만들어진 것은
> `lib/ui/screens/class_management_screen.dart` 와
> `test/ui/class_management_screen_test.dart` 이고, 대기·단정 헬퍼는
> `test/helpers/widget_test_helpers.dart` 로 공용화되어 회원 관리 테스트와 공유한다.
> 남은 UI 태스크는 **그 두 파일을 본으로 삼을 것.**
>
> 본문에 대해 적용한 정정 8건 (브리프:
> `.superpowers/sdd/2026-09-18-checkin-app/task-15-brief.md`):
> 1. 대기·단정 헬퍼를 `test/helpers/widget_test_helpers.dart` 로 공용화
> 2. 목록 단정을 `ListTile` 안으로 한정 + 저장 뒤 다이얼로그 닫힘 확인
> 3. 요일 라벨을 `요일 1` → `월`~`일`
> 4. 이름·시작 시간(`HH:mm`)·운영 요일 최소 1개를 저장 시점에 검증 (아래 이유)
> 5. `ClassRepository.delete` 가 `members.class_id` 를 NULL 로 정리 (Task 14 이월)
> 6. 삭제에 확인 다이얼로그 — 소속 회원의 반 지정이 해제된다는 사실을 문구에 넣음
> 7. **수정 기능을 범위에 추가** (본문은 추가·삭제만이었다). 정정 5 때문에 반 삭제가 소속
>    회원 전원의 반 지정을 지우는 동작이 되어, 수정 경로가 없으면 시작 시간 오타를 고치려고
>    반을 지우고 다시 만드는 순간 그 반 회원 전원의 반 지정이 날아간다.
> 8. 화면 구조를 Task 14 패턴에 맞춤 (양식은 별도 `StatefulWidget` + 컨트롤러 `dispose`,
>    양식은 모델만 돌려주고 쓰기는 화면이, `_loaded` + 로딩 표시, `await` 뒤 `mounted` 확인)
>
> **정정 4 를 넣은 이유:** 본문은 입력칸 텍스트를 검증 없이 `startTime` 에 넣었다.
> `ClassModel.startDateTimeFor` 가 그 값을 `:` 로 쪼개 `int.parse` 하므로, `15시`·`3:00 PM`·
> 빈 문자열이 들어가면 **그 자리가 아니라 Task 18 의 결석 처리가 돌 때** 터진다. 운영 요일이
> 비어 있는 반은 `operatesOn` 이 항상 false 여서 결석 처리가 영원히 돌지 않는다.
> 검증 3종은 변이 검증으로 실제로 막는 것을 확인했다 (validator 를 하나씩 무력화하면 해당
> 테스트 하나만 실패).
>
> **남은 선택지 하나:** 시작 시간 정규식이 두 자리 시(`09:00`)만 받아서 `9:00` 은 거부된다.
> `int.parse('9')` 는 되므로 런타임 위험은 없고, 저장 형식을 일정하게 유지하려는 의도다.
> 관리자 편의를 더 보려면 `9:00` 을 받아 `09:00` 으로 정규화하는 쪽으로 바꿀 수 있다.

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

> ✅ **구현 완료** (2026-10-17): `77338bd`, `6af5ddf`, `31e116c`, `fe5acbf`, `baf61fd`.
>
> **아래 본문의 Step 1·3 코드는 폐기됐다. 베끼면 컴파일조차 안 된다.** 2026-10-16 개정 전에
> 쓰였기 때문이다: `controller.qrUrl` 은 존재하지 않고(개정으로 QR 이 2종이 되어 지금은
> `checkInUrl`·`checkOutUrl` 두 개), `CheckInServer` 생성자도 인자 4개로 적혀 있으나 실제는
> 7개다. 더 중요하게는 **하원 현황과 미하원이 빠져 있었다.**
>
> 실제 결과물: `lib/ui/screens/dashboard_screen.dart`, `lib/ui/attendance_labels.dart`,
> `test/ui/dashboard_screen_test.dart`.
> 브리프: `.superpowers/sdd/2026-09-18-checkin-app/task-16-brief.md`.
>
> 적용한 것:
> - QR 2종을 **"등원"·"하원" 라벨과 함께** 그린다. 라벨 없는 QR 두 개는 학생이 등원 QR 로
>   하원을 찍게 만든다.
> - 요약 `등원 N · 하원 N · 체류 중 N · 미하원 N`. 상태 라벨은 한글
>   (`lib/ui/attendance_labels.dart` 에 모았고 **Task 17 도 같은 파일을 쓴다**).
> - 새로고침 간격을 생성자로 주입하고 `dispose` 에서 취소한다 (안 하면 위젯 테스트가
>   pending timer 로 실패한다). `clock` 주입으로 시각을 고정해 테스트한다.
> - `bool _loaded` + 첫 로드 전 로딩 표시.
>
> ### ⚠️ 미하원의 정의 — 스펙이 이긴 건 (Task 17·18 도 이걸 따를 것)
>
> 작업 중 브리프가 미하원을 `checkOutTime == null` 로 적었는데 **틀렸다.** 스펙
> (`2026-09-18-checkin-app-design.md` 75~77행)은 **등원 있음 + 하원 없음 + 등원으로부터
> 12시간 경과**로 정하고, 그 조건으로 **보정 대상**을 찾는다고 말한다. `CLAUDE.md` 규칙대로
> 스펙이 이긴다. 서로 다른 두 상태를 구별해야 한다:
>
> - **체류 중** — 하원 없음, 12시간 **이내**. 하원 QR 로 아직 닫을 수 있어 관리자가 할 일이
>   없다. "지금 안에 있는 사람"이다.
> - **미하원** — 하원 없음, 12시간 **경과**. QR 로는 못 닫으므로 **사람이 보정해야 한다.**
>
> 12시간 경계가 둘을 가르는 이유가 이것이다. **판정을 화면에서 다시 계산하지 말 것** —
> 저장소의 세 메서드가 창을 나눠 가진다:
> | 메서드 | 조건 | 뜻 |
> |---|---|---|
> | `findOpenSessionsWithin` | 하원 없음, `check_in_time >= now-12h` | 체류 중 |
> | `findUnclosedSessions` | 하원 없음, `check_in_time < now-12h` | 미하원 (보정 대상) |
> | `findSessionsWithin` | 닫힌 것 포함, `check_in_time >= now-12h` | 최근 방문 전체 |
>
> `>=` 와 `<` 로 갈라서 열린 세션은 앞의 두 메서드 중 **정확히 하나에만** 나온다 (틈도 겹침도
> 없음을 경계 테스트로 확인했다).
>
> ### 자정을 넘긴 방문이 화면에서 사라지던 구멍
>
> `getByDate(오늘)` 만 읽으면 어제 23:50 등원해 아직 안 나간 사람이 자정 이후 사라지고,
> 00:20 에 하원하면 행 날짜가 어제여서 **그 방문의 흔적이 대시보드에서 완전히 없어진다.**
> 개정이 공들인 바로 그 경로에 눈먼 구간이 생기므로 `findSessionsWithin` 을 추가해 닫힌 과거
> 세션까지 보이게 했다.
>
> **요약 숫자는 오늘 행만 센다.** 어제 등원한 방문을 "오늘 등원 N" 에 더하면 그 숫자가 거짓이
> 되므로, 과거에서 이어진 방문은 `이전 날짜에서 이어진 방문` 구역에 날짜와 함께 따로 보인다.

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

> ✅ **구현 완료** (2026-10-17): `204d301`, `9e3a4db`. 테스트 193개.
>
> **아래 본문의 Step 1·3 코드는 폐기됐다.** 2026-10-16 개정 전에 쓰였고 **출결 보정 기능이
> 아예 없었다.** 보정은 학생이 QR 을 못 찍었거나 잘못 찍은 것을 사람이 바로잡는 유일한
> 경로다. 하원 시각·미하원도 없었고, `월간` 이라고 하면서 전체 기간을 셌다.
>
> 실제 결과물: `lib/ui/screens/attendance_history_screen.dart`,
> `test/ui/attendance_history_screen_test.dart`.
> 브리프: `.superpowers/sdd/2026-09-18-checkin-app/task-17-brief.md`.
>
> 적용한 것:
> - 행마다 날짜·상태(한글)·등원·하원 시각. 하원이 행 날짜의 다음 날이면 `(다음 날)` 을
>   드러낸다 — 안 드러내면 관리자가 `등원 23:50 / 하원 00:20` 을 음수 체류로 읽는다.
> - **보정 양식**: 상태, 등원 시각, 하원 시각. 하원 시각을 비우면 null (미하원으로 되돌림).
>   하원이 등원보다 이르면 자정을 넘긴 방문으로 보고 다음 날로 조립한다.
>   등원 없이 하원만 있는 조합은 거부한다.
> - 월별 집계는 **선택한 달만** 센다. 미하원은 Task 16 의 12시간 정의를 따른다.
>
> ### ⚠️ `Attendance.copyWith` 를 추가하지 않았다 — 이월 사항의 지시를 철회한 것
>
> 이 계획서의 이월 사항은 "보정 화면을 만들기 전에 `Attendance.copyWith` 를 추가할 것" 이라고
> 적었다. **그 지시를 철회했다.** Task 14 에서 같은 길을 가봤고 막혔기 때문이다:
> nullable 필드를 `값 ?? this.값` 으로 합치는 `copyWith` 는 **값을 지우는 수정을 표현할 수
> 없다** (`null` 이 "바꾸지 않음" 과 구별되지 않는다). 보정은 **하원 시각을 지워야 하는
> 경우가 실제로 있다** — 잘못 찍힌 하원 되돌리기. Task 14 는 `clearParentContact` 플래그로
> 때우려 했으나 `classId` 도 지워야 해서 플래그를 필드마다 늘리는 길이 되었고, 결국 양식이
> 모델을 **전체 생성**하는 쪽으로 갔다.
>
> 그래서 보정 양식도 기존 행에서 출발해 `Attendance` 를 전체 생성하고 `update` 에 넘긴다.
> 이러면 이월 사항이 걱정한 원래 위험("`update` 호출자가 필드를 빠뜨리면 조용히 null 이 된다 —
> `check_out_time` 포함")도 같이 사라진다. `lib/models/attendance.dart` 는 건드리지 않았다.
>
> ### 보정은 학부모 알림을 내지 않는다 (스펙 81~83행)
>
> 이 화면은 `NotificationService` 를 주입받지 않는다 — 구조적으로 알림을 낼 수 없다.
> 더해서 `notification_logs` 가 늘지 않는 것을 테스트로 증명한다. **처음 작성된 테스트는
> 0건에서 0건으로 끝나서 `getRecent()` 가 항상 빈 값을 줘도 통과했다** — 아무것도 막지 못하는
> 테스트였다. 알림 1건을 미리 심고 보정 뒤에도 그 1건이 그대로인지 보는 형태로 바꿨고,
> 하원 시각 보정 케이스를 추가했다. 상태 변경보다 하원 보정이 위험하다 — 학생이 하원 QR 을
> 찍은 것과 결과가 같아 보여서 알림 경로에 얽히면 바로 거짓 알림이 나간다.
>
> ### `HH:mm` 검사는 `lib/ui/hhmm.dart` 한 곳에 있다
>
> 반 관리 화면과 보정 양식이 같은 정규식을 각자 들고 있었다. 이 검사를 통과하지 못한 값이
> 저장되면 그 자리가 아니라 나중에 다른 곳에서 터지므로(`startDateTimeFor` 의 `int.parse`,
> 보정의 ISO8601 조립) 규칙이 두 벌로 갈라지면 안 된다. 시각을 입력받는 화면은 이걸 쓸 것.

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

> ✅ **구현 완료**: `lib/services/absence_scheduler.dart`, `lib/repositories/app_state_repository.dart`,
> `lib/main.dart`, `test/services/absence_scheduler_test.dart`, `test/main_smoke_test.dart`.
>
> **아래 본문의 Step 1·3·5 코드는 폐기됐다.** 2026-10-16 개정 전에 쓰여서:
> - 스케줄러가 "마지막 처리 날짜"를 메모리에만 두어 PC 가 꺼져 있던 날을 따라잡지 못한다.
>   스펙 11번대로 `app_state` 에 저장하고 시작 시 어제까지 하루씩 따라잡도록 바꿨다
>   (`AppStateRepository` 신설, 하루 처리할 때마다 저장).
> - `CheckInServer` 생성자 인자가 4개로 적혀 있으나 실제는 7개이고, 서버와 컨트롤러가
>   `QrTokenService` 를 **각자 만들면** 화면의 QR 토큰을 서버가 모른다 — 하나를 공유한다.
> - 스모크 테스트가 찾는 문구는 '실시간 현황' 이다 ('실시간 체크인 현황' 아님).
> - 첫 실행(저장된 날짜 없음)은 소급 처리 없이 어제까지 처리한 것으로 기록한다.

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

## 모든 태스크 뒤: 수동 스모크 테스트

> 2026-10-27 개정. **이전 체크리스트는 개정 전 설계를 서술했다** — QR 1개, 뒷 4자리 확인 없음,
> "이름만 고르면 바로 체크". 그대로 따르면 지금 앱에 없는 동작을 찾게 된다.
>
> **자동 테스트 222개가 증명하지 못하는 것이 여기 있다.** 위젯 테스트는 가짜 시간에서 돌고
> 서버 테스트는 `localhost` 로 때린다. **다른 기기가 LAN 을 건너 들어오는 경로**는 실제 폰으로만
> 확인된다. 실패하면 대개 코드가 아니라 환경이다 (아래 마지막 항목).

### PC 쪽

- [ ] `flutter run -d windows` 로 띄우고, 대시보드 탭에 **QR 이 2개** 뜨고 각각 **"등원"·"하원"**
      라벨이 붙는지 확인한다. 두 QR 의 그림이 서로 달라야 한다.
- [ ] QR 이 30초마다 바뀌는지 본다. 안 바뀌면 회전 타이머가 죽은 것이다.
- [ ] 반 탭에서 반을 하나 만든다 (시작 시간 `HH:mm`, 운영 요일 1개 이상 — 안 넣으면 저장이 막힌다).
- [ ] 회원 탭에서 회원을 둘 만든다: 하나는 **학부모 연락처 있음**, 하나는 **연락처 없음**.
      연락처 없는 쪽에 "관리자 대행" 안내가 붙는지 확인한다.
- [ ] 앱을 끄고 다시 띄워 **반과 회원이 남아 있는지** 확인한다 (파일 DB 가 실제로 쓰이는지).

### 폰 쪽 — 같은 WiFi 에 붙은 폰으로

- [ ] **등원 QR** 을 스캔한다. 페이지가 열리고 제목이 등원인지 확인한다.
- [ ] 명단에서 연락처 있는 회원을 고르고 **연락처 뒷 4자리**를 넣는다 → 바인딩 + 등원 기록.
      대시보드에 **완료 배너**가 뜨고 목록에 그 회원이 나타나는지 본다.
- [ ] **등원 QR 을 다시 스캔**한다 → "이미 등원" 이어야 한다. 하원으로 넘어가면 안 되고,
      학부모 알림이 두 번 생겨도 안 된다 (점검 탭에서 알림 내역 1건인지 확인).
- [ ] 이제 **하원 QR** 을 스캔한다 → 하원 기록. 대시보드에서 그 회원이 체류 중에서 빠지는지 본다.
- [ ] **4자리를 틀리게 5번** 넣어본다 → 잠긴 뒤에는 올바른 4자리를 넣어도 통과하지 않아야 한다.
- [ ] **연락처 없는 회원**: 회원 탭에서 그 회원의 **연동 코드를 발급**받아 폰에 입력한다 →
      바인딩된다. 코드는 5분 뒤 만료되고 한 번 쓰면 사라진다.
- [ ] 바인딩된 폰으로 다시 스캔하면 **이름 고르기와 4자리 없이** 바로 체크되는지 확인한다.
- [ ] "다른 사람으로 체크" 버튼으로 바인딩을 바꿀 수 있는지 확인한다.

### 관리자 화면

- [ ] 기록 탭에서 회원을 골라 등원·하원 시각과 상태가 보이는지 확인한다.
- [ ] **보정**을 해본다 (하원 시각을 비워 저장 → 미하원으로 돌아가는지).
      보정 뒤 **점검 탭의 알림 내역이 늘지 않아야 한다** — 보정은 학부모 알림을 내지 않는다.
- [ ] 점검 탭에서 알림 내역과 바인딩 이력이 보이는지 확인한다. 같은 기기가 다른 회원으로
      묶인 적이 있으면 경고가 붙는다.

### 안 되면 여기부터 — 대개 코드가 아니라 환경이다

- [ ] **Windows 방화벽이 8080 을 막는지.** `flutter run` 첫 실행 때 뜨는 허용 창을 놓쳤으면
      인바운드 규칙을 직접 열어야 한다. 폰에서 페이지가 아예 안 열리면 1순위 원인이다.
- [ ] **공유기의 AP isolation (기기 간 통신 차단).** 켜져 있으면 같은 WiFi 라도 폰이 PC 에
      닿지 못한다. 게스트 WiFi 는 보통 켜져 있다.
- [ ] **PC 가 유선, 폰이 무선**이면 같은 서브넷인지 확인한다.
- [ ] QR 의 주소가 `http://192.168.x.x:8080/...` 인지 본다. 주소가 안 뜨면
      (`네트워크를 찾을 수 없습니다`) 로컬 IPv4 탐색이 실패한 것이다 — VPN 어댑터가 흔한 원인이다.

### 실사용 전에 반드시

- [ ] **`DatabaseHelper` 에 `onUpgrade` 를 붙인다.** 지금 `version: 1` 에 마이그레이션이 없는데
      앱이 `getApplicationSupportDirectory()/checkin_app.db` 에 실제 파일을 만든다. 출결
      데이터가 쌓인 뒤 스키마를 한 번이라도 바꾸면 **그 데이터를 옮길 길이 없다.**
      지금은 구버전 DB 파일을 가진 사람이 없어(이전 `main.dart` 는 DB 를 열지 않았다) 안전하다.
- [ ] 설치하는 PC 의 **DB 파일 경로에 한글이 섞이는지** 확인한다 (`sqflite_common_ffi` 가
      Windows 에서 열지 못할 수 있다). 개발 PC 는 `C:\Users\kkh\...` 로 ASCII 라 문제없었다.
