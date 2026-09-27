# CheckInApp

학원·헬스장 등에서 쓰는 출결 관리 프로그램. Flutter Desktop(Windows) 관리자 앱 하나가
SQLite와 체크인용 로컬 HTTP 서버를 같은 프로세스 안에서 함께 굴린다. 학생은 카운터 화면에
뜬 QR을 자기 폰으로 스캔해서 직접 출석을 찍는다.

## 함정

- **폴더명과 패키지명이 다르다.** 폴더는 `checkInApp`, Dart 패키지는 `checkin_app`.
  import는 항상 `package:checkin_app/...` — 폴더명을 따라가면 컴파일이 깨진다.
- **데스크톱 SQLite는 `sqflite`가 아니라 `sqflite_common_ffi`.** 쓰기 전에
  `sqfliteFfiInit()`을 부르고 `databaseFactory = databaseFactoryFfi`를 세팅해야 한다.
  테스트도 마찬가지 (`test/helpers/test_db.dart`가 이걸 대신 해준다 — 새로 만들지 말고 쓸 것).

## 명령어

```bash
flutter test                  # 전체 테스트
flutter test test/some_test.dart   # 단일 파일
flutter run -d windows        # 앱 실행 (Windows 데스크톱)
flutter pub get               # 의존성
```

## 아키텍처 불변조건

바꾸려면 스펙 문서부터 고쳐야 하는 결정들:

- **외부 서버 없음.** 클라우드 호스팅을 쓰지 않는다 (비용 문제로 배제된 결정). 체크인
  페이지는 학원 로컬 네트워크 안에서만 열린다.
- **서버는 앱과 한 프로세스.** 로컬 HTTP 서버와 관리자 UI가 같은 SQLite 핸들을 직접
  공유한다 — 둘 사이에 별도 통신 계층을 만들지 않는다.
- **QR 토큰은 주기적으로 갱신된다.** 카운터에 가야만 현재 코드를 볼 수 있다는 점이
  부정 출석을 막는 핵심 장치다. 고정 토큰으로 단순화하지 말 것.
- **회원 1명은 반 1개에만 속한다.** `Member.classId`는 단일 nullable 필드.

## 관례

- **커밋 메시지는 한글로.** 타입 접두사(`feat:`, `fix:`, `chore:`)만 영어로 유지.
- 이 저장소는 worktree 없이 `main`에서 직접 작업한다.

## 권위 문서

- 설계 스펙: `2026-09-18-checkin-app-design.md` — 무엇을 왜 만드는지의 최종 근거
- 구현 계획: `docs/superpowers/plans/2026-09-18-checkin-app.md` — 태스크 단위 실행 계획

계획과 스펙이 충돌하면 스펙이 이긴다.
