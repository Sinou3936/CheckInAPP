# QR 단일화 — 남은 작업 (2026-10-27 기준)

이어받는 사람을 위한 문서다. 전체 계획은 [`2026-10-27-single-qr.md`](2026-10-27-single-qr.md),
승인된 설계는 [`../specs/2026-10-27-single-qr-design.md`](../specs/2026-10-27-single-qr-design.md),
권위 스펙은 저장소 루트의 `2026-09-18-checkin-app-design.md` 다. 계획과 스펙이 충돌하면 스펙이 이긴다.

---

## 지금 상태 — 먼저 읽을 것

**Task 1~6·8 과 Task 9 의 배선까지 끝나 있고, `flutter analyze` 는 No issues, 자동 테스트
265개가 전부 통과한다.** 남은 것은 **Task 7(체크인 페이지)**, **Task 9 의 화면 부분(설정 탭)**,
**Task 10(마감)** 이다.

**가장 중요한 것부터: 지금 상태로는 학생 폰에서 체크가 안 된다.** `lib/server/checkin_page.dart`
는 HTML 을 원시 문자열로 들고 있어서 **컴파일은 되지만 동작이 낡았다** — 사라진
`/api/session` 응답의 `kind` 로 제목을 정하고, `/api/checkin` 에 `actionId` 없이 쓴다.
서버는 `actionId` 없는 요청을 `400 bad_request` 로 거부한다. 자동 테스트는 이 문자열을
문법적으로만 보기 때문에 **초록인데도 깨져 있다.** Task 7 이 그것을 고친다.

### 커밋된 것

| 커밋 | 내용 |
|---|---|
| `626ce31` | 설계 승인본 — 제3자 검토 5건을 스펙 근거로 판정해 반영 |
| `5849dc5` | 구현 계획 10개 태스크 |
| `6871182` | 권위 스펙 개정 (QR 2종 → 단일 QR + 최소 체류 시간) |
| (Task 2) | `MinimumStayService` (`app_state`, 기본 30분) |
| `561daf5` | 이 문서의 첫 판 |
| (단일 QR 전환) | Task 3·4·5·6·8 + Task 9 의 `main.dart` 배선. analyze 0건, 테스트 265개 통과 |

`main.dart` 는 `MinimumStayService` 를 **하나** 만들어 서버에 넘긴다. 설정 화면도 같은
인스턴스를 받아야 한다 — 서버가 요청마다 `read()` 하므로 캐시 무효화는 필요 없다.

### 이미 만들어진 인터페이스 (남은 작업이 쓸 것)

```dart
// lib/models/check_kind.dart — QR 의 종류가 아니라 "기록되는 행동"
enum CheckKind { checkIn, checkOut }

// lib/services/qr_token_service.dart — 토큰 하나
String get token;
void rotate({DateTime? now});
bool isValid(String token, {DateTime? now});

// lib/services/verification_session_service.dart — 세션은 종류를 담지 않는다
String issue({DateTime? now});
bool isValid(String sessionId, {DateTime? now});
String? registerAction(String sessionId, CheckKind kind, {DateTime? now});
CheckKind? actionOf(String sessionId, String actionId, {DateTime? now});
void consume(String sessionId);   // 그 세션의 action id 전부가 함께 죽는다

// lib/services/minimum_stay_service.dart
static const String stateKey = 'minimum_stay_minutes';
static const Duration defaultValue = Duration(minutes: 30);
static const Duration minimum = Duration(minutes: 1);
static const Duration limit = Duration(hours: 12);   // 미만
static bool isAllowed(Duration value);
Future<Duration> read();      // 깨진 값이면 defaultValue, 예외 없음
Future<void> write(Duration value);   // 범위 밖이면 ArgumentError

// lib/services/attendance_service.dart
enum CheckAction { checkIn, checkOut, choice, tooEarly, overdue, alreadyCheckedOut }
class CheckJudgment { CheckAction action; Duration? remaining; Attendance? openSession;
                      Set<CheckKind> get allowedKinds; }
Future<CheckJudgment> judge(int memberId, {required Duration minimumStay, DateTime? now});
Future<CheckOutOutcome> recordCheckOut(int memberId,
    {required Duration minimumStay, DateTime? now});
enum CheckOutStatus { recorded, noOpenSession, alreadyCheckedOut, tooEarly }

// lib/services/checkin_event_bus.dart
enum CheckEventKind { checkedIn, checkedOut, blockedTooEarly, blockedOverdue }
class CheckInEvent { String memberName; CheckEventKind kind; bool isLate; Duration? remaining; }

// lib/services/checkin_app_controller.dart
final ValueNotifier<String?> qrUrl;   // checkInUrl / checkOutUrl 을 합친 것

// lib/server/checkin_server.dart — 생성자에 추가된 것
required MinimumStayService minimumStayService,
DateTime Function() clock = DateTime.now,
```

### 서버가 이미 제공하는 HTTP 계약

- `GET /api/session?token=` → `200 {"sessionId": "..."}` / `403 {"error":"invalid_token"}`.
  **`kind` 를 돌려주지 않는다.**
- `GET /api/next-action?session=&deviceToken=` →
  `403 {"error":"invalid_session"}` / `400 {"error":"member_required"}` /
  ```json
  {
    "action": "checkIn|checkOut|choice|tooEarly|overdue|alreadyCheckedOut",
    "memberName": "홍길동",
    "remainingMinutes": 18,
    "openSession": {"date": "2026-10-26", "checkInTime": "23:50"},
    "actions": [{"id": "…", "kind": "checkOut"}]
  }
  ```
  `remainingMinutes` 는 `tooEarly` 에서만(올림), `openSession` 은 근거 행이 있을 때만,
  `actions` 는 `checkIn`·`checkOut` 에 하나 · `choice` 에 둘(**하원이 먼저**) · 나머지에 `[]`.
  `tooEarly`·`overdue` 를 읽는 순간 카운터에 차단 배너 이벤트가 발행된다. 기록은 하지 않는다.
- `POST /api/checkin {session, deviceToken, actionId}` →
  `400 bad_request` / `403 invalid_session` / `403 {"error":"invalid_action"}` /
  `400 member_required` / `400 {"error":"no_open_session"}` /
  `409 {"error":"state_changed", …next-action 과 같은 판정 본문}` /
  `200 {"result":"checkedIn","memberName":"…","status":"present|late"}` /
  `200 {"result":"checkedOut","memberName":"…"}` /
  `200 {"result":"alreadyCheckedIn"|"alreadyCheckedOut","memberName":"…"}`.
  본문의 다른 필드(예: `kind`)는 **보지 않는다.** 성공하면 세션을 소비한다. `409` 는
  소비하지 않는다 — 학생이 새 판정을 보고 한 번 더 누른다.

---

## Task 7 — 체크인 페이지의 확인 단계

**파일:** `lib/server/checkin_page.dart` (수정), `test/server/checkin_page_route_test.dart` (수정)

이 페이지는 HTML 한 장이라 테스트는 라우트와 본문 문자열을 본다. 먼저 테스트를 고쳐
실패를 확인하고(현재 테스트는 `kind === 'checkOut'` 을 단정한다) 그 다음 페이지를 고친다.

### 테스트에 들어갈 단정

```dart
test('페이지가 kind 를 서버로 보내지 않는다', ...);   // 본문에 "kind:" 가 없다
test('페이지가 /api/next-action 을 부른다', ...);
test('여섯 판정 문구가 모두 들어 있다', ...);
test('state_changed 를 재확인 화면으로 되돌린다', ...);  // "'state_changed'" 포함
test('외부 리소스를 참조하지 않는다', ...);   // 기존 단정 유지 (http:// https:// 없음)
```

- 기존 `'페이지는 스캔한 QR 종류가 하원인지를 읽는다'` 테스트는 **지운다** — 그 보증이
  사라진 자리를 위 첫 번째 테스트가 대신 지킨다.
- 기존 `'페이지는 Task 11 의 결과 코드를 모두 다룬다'` 목록에 `'state_changed'`,
  `'invalid_action'` 을 더한다.
- 기존 엔드포인트 목록에 `/api/next-action` 을 더한다.

### 흐름

`GET /api/session?token=` → 기기 토큰(localStorage) → (필요하면 이름+뒷 4자리로 `/api/bind`)
→ `GET /api/next-action` → **확인 화면** → 학생이 누름 → `POST /api/checkin {session,
deviceToken, actionId}` → 결과 화면.

### 확인 화면 문구

| action | 문구 | 버튼 |
|---|---|---|
| `checkIn` | "OOO 님, 등원하시겠습니까?" | [등원] |
| `checkOut` | "OOO 님, 하원하시겠습니까?" | [하원] |
| `choice` | "OOO 님, M월 D일 HH:mm 등원 기록이 열려 있습니다." | [하원하기] [새로 등원하기] |
| `tooEarly` | "방금 등원했습니다. N분 뒤에 하원할 수 있습니다." | 없음 |
| `overdue` | "하원 시간이 지났습니다. 관리자에게 문의해 주세요." | 없음 |
| `alreadyCheckedOut` | "오늘은 이미 하원했습니다." | 없음 |

- 버튼은 `actions` 배열을 그대로 그린다. `kind` 로 라벨을 정하고 **`id` 만 보낸다.**
- `tooEarly`·`overdue` 는 `state-fail`, `alreadyCheckedOut` 은 `state-again` 으로 화면 전체
  색을 바꾼다(기존 `setState` 규약 그대로). **확인 화면은 색을 바꾸지 않는다** — 아직 아무
  일도 일어나지 않았다.
- `409 state_changed` 를 받으면 응답 본문의 판정으로 확인 화면을 **다시 그리고**
  "상태가 바뀌었습니다. 다시 확인해 주세요." 를 덧붙인다. 응답 모양이 `/api/next-action`
  과 같으므로 같은 렌더 함수를 쓸 수 있다.
- 버튼은 누른 즉시 `disabled` 로 바꾼다. 두 번 눌려도 두 번째는 세션이 소비돼
  `invalid_session` 이 되지만, 화면이 깜빡이면 학생이 불안해한다.
- `invalid_action` 은 더 진행할 수 없는 오류로 다룬다(`showError(UNEXPECTED)`).

---

## Task 9 — 설정 탭 (배선은 끝남, 화면만 남음)

**파일:** `lib/ui/screens/settings_screen.dart` (신규), `lib/main.dart` (탭 추가만),
`test/ui/settings_screen_test.dart` (신규), `test/main_smoke_test.dart` (수정)

`main.dart` 의 `MinimumStayService` 생성과 서버 주입은 이미 들어가 있다. 남은 것은 화면과
`_HomeShellState.build` 의 탭 추가다.

```dart
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.minimumStayService});
  final MinimumStayService minimumStayService;
}
```

### 테스트에 들어갈 단정

```dart
test('현재 값을 분으로 보여준다', ...);                  // 기본 30
test('값을 바꿔 저장하면 저장소에 들어간다', ...);        // read() == 45분 + 저장 확인 문구
test('하한 미만은 거부하고 저장하지 않는다', ...);        // '0'
test('12시간 이상은 거부한다', ...);                     // '720'
test('숫자가 아니면 거부한다', ...);
test('아주 짧은 값은 경고를 함께 보여준다', ...);         // 5분: 재스캔 보호가 약해진다
test('탭이 여섯 개이고 설정 탭이 있다', ...);             // main_smoke_test
```

로드 전에는 `CircularProgressIndicator` 를 그리고, 테스트는
`pumpUntil(tester, () => absent(find.byType(CircularProgressIndicator)))` 로 기다린다.

### 구현 메모

- 검증은 **`MinimumStayService.isAllowed` 를 쓴다.** 화면이 따로 숫자를 적으면 화면은
  통과시키는데 저장은 거부하는 조합이 생긴다. 거부 문구에 하한·상한을 그대로 적는다.
- `main.dart`: `MinimumStayService(AppStateRepository(db))` 를 **한 개** 만들어
  `CheckInServer` 와 `SettingsScreen` 이 같은 인스턴스를 쓰게 한다. 서버는 요청마다
  `read()` 하므로 캐시 무효화가 필요 없다 — 설정을 바꾸면 그 다음 요청부터 새 값이다.
- 탭은 현황·회원·반·기록·점검 뒤에 '설정'(`Icons.settings`).

---

## Task 10 — 마감

1. **위조 방지 보증 세 가지에 테스트가 있는지 확인한다.** 예전 보증("토큰이 둘로 분리돼
   있어서 등원 QR 로 하원을 못 만든다")은 사라졌다. 지금 보증은:
   - 클라이언트가 종류를 보낼 수 없다 → `checkin_server_write_test.dart`
     "본문의 kind 는 무시되고 action id 가 정한 것이 기록된다"
   - action id 가 세션에 묶여 있다 → 같은 파일 "다른 세션의 action id 는 403 invalid_action"
   - 최소 체류 시간 안에는 하원이 되지 않는다 → `attendance_service_test.dart` 의 판정 4·7번과
     "recordCheckOut 은 최소 체류 시간 안에는 하원을 기록하지 않는다"
2. **돌연변이로 검증한다.** `attendance_service.dart` 의 `elapsed < minimumStay` 비교를 잠시
   뒤집고 `flutter test` 를 돌려 **실패하는지** 본다. 통과하면 그 테스트는 아무것도 막지
   않는다. 확인한 뒤 되돌린다.
3. **수동 스모크 체크리스트를 고친다** (`2026-09-18-checkin-app.md` 안에 있다). 지금은 QR
   2종 흐름이다. 단일 QR 흐름으로 바꾸고 다음을 넣는다:
   - 폰으로 QR 스캔 → 확인 화면 문구 → [등원] → 기록
   - **곧바로 재스캔** → "방금 등원했습니다. N분 뒤에…" + 카운터에 차단 배너
   - 설정에서 최소 체류 시간을 1분으로 바꾸고 다시 스캔 → 하원이 되는지
   - 하원 뒤 재스캔 → "오늘은 이미 하원했습니다"
   - 한글이 들어간 경로에서 DB 가 열리는지 (Task 18 에서 남은 확인)
4. **설계 문서 상태 줄**을 구현 완료로 바꾼다.
5. `dart format lib test` → `flutter analyze` (No issues) → `flutter test` (전부 통과) 를
   **Windows 에서 실제로 돌려** 확인하고 커밋한다.

---

## 이미 내린 판정 (ledger 사본)

바꾸고 싶으면 바꿔도 되지만, 왜 그렇게 했는지는 알고 바꿀 것.

- **커밋 경계를 컴파일 가능성에 맞췄다.** `QrKind` 제거와 `recordCheckOut(minimumStay:)`
  필수화가 서버·페이지·컨트롤러·화면·main 을 동시에 깨므로, 태스크별 커밋 대신 트리가
  초록인 지점에서 끊는다. 비용: Task 3~8 이 한 커밋이라 되돌릴 때 한꺼번에 되돌아간다.
- **`CheckInServer` 에 `clock` 을 주입했다.** 최소 체류 시간과 12시간 경계는 실제 시각으로
  재현할 수 없다 — 오후에만 통과하는 테스트가 된다. 대시보드가 이미 쓰는 패턴이다.
  비용: 생성자 인자 하나.
- **QR 크기를 `min(360, 화면높이 × 0.45)` 로 두고 대시보드 위젯 테스트 화면을 1280×1000 으로
  키웠다.** 320 고정 + 기본 테스트 화면(800×600)에서는 목록 행이 화면 밖으로 밀려
  "없다"로 잘못 단정됐다. 비용: 창이 아주 작으면 QR 도 작아진다.
- **`remainingMinutes` 는 올림이다.** 90초 남았는데 "1분 뒤"라고 하면 그 학생은 한 번 더
  헛걸음한다.
- **`choice` 에서 하원을 먼저 보여준다.** 그 상태에 오는 사람은 나가는 쪽이 더 흔하다.
- **차단된 시도는 DB 에 쓰지 않는다.** 카운터 배너만 띄운다. 남기려면 테이블이 하나
  필요하고, 그건 이번 작업이 피하기로 한 스키마 변경이다. 비용: 나중에 "그날 누가 일찍
  나가려 했나"를 되짚을 방법이 없다.

---

## 이 계획 밖의 후속 작업

- **스펙 문서를 개정 날짜별로 분리한다** (2026-10-27 사용자 요청). 지금
  `2026-09-18-checkin-app-design.md` 한 장에 모든 개정이 쌓여 있다. 이번 구현을 마친 뒤 별건.
- **`DatabaseHelper.onUpgrade` 를 붙인다.** 아직 `version: 1` 에 마이그레이션이 없는데 앱이
  `getApplicationSupportDirectory()/checkin_app.db` 에 실제 파일을 만든다. 출결 데이터가
  쌓인 뒤 스키마를 한 번이라도 바꾸면 그 데이터를 옮길 길이 없다. **실사용 전 필수.**
- **카운터 화면에서 한 번 눌러 하원 처리하기.** 이번 범위 밖으로 뒀다. 차단 배너까지는
  넣었으니 직원이 모르는 상태는 없다. 보정 6단계가 실제로 불편하면 그때 별건으로.
- `Attendance.copyWith` 의 `clearParentContact` 는 프로덕션 호출자가 없다 (단위 테스트만).
  제거 여부 판단.
- `lib/ui/hhmm.dart` 가 `9:00` 을 거부한다 (두 자리 시만 허용). `09:00` 으로 정규화할지 결정.
- 테스트 로그의 `*** sqflite warning ***` 소음 정리.
- `backup-before-rewrite` 브랜치 삭제 여부 (main 에 없는 커밋 14개를 들고 있는 안전망).

---

## 검증 명령

```bash
dart format lib test
flutter analyze          # "No issues found!" 여야 한다
flutter test             # 전부 통과여야 한다
```

`flutter run` 은 돌리지 않는다 (저장소 관례). Windows 에서 돌릴 것 — Task 18 이 Flutter 없는
환경에서 작성돼 빨간 상태로 들어온 선례가 있다.
