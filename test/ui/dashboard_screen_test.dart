import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:checkin_app/models/attendance.dart';
import 'package:checkin_app/models/member.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/bind_attempt_throttle.dart';
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/services/checkin_event_bus.dart';
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/notification_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/services/verification_session_service.dart';
import 'package:checkin_app/ui/screens/dashboard_screen.dart';

import '../helpers/test_db.dart';
import '../helpers/widget_test_helpers.dart';

/// 이전 날짜에서 이어진 방문 구역의 제목. 화면과 같은 글자여야 한다.
const previousSectionTitle = '이전 날짜에서 이어진 방문';

const _checkInUrl = 'http://192.168.0.10:8080/checkin?token=IN-TOKEN';
const _checkOutUrl = 'http://192.168.0.10:8080/checkin?token=OUT-TOKEN';

/// 테스트 중에 새로고침 타이머가 끼어들지 않도록 충분히 긴 간격을 쓴다.
const _quietInterval = Duration(hours: 1);

/// 기본 현재 시각. 실제 시계에 기대지 않도록 고정한다 — 12시간 경계 시나리오가 시계에 따라 깨지면 안 된다.
final kNow = DateTime(2026, 10, 17, 12, 0);
final kToday = DateTime(2026, 10, 17);
final kYesterday = DateTime(2026, 10, 16);

class DashboardHarness {
  final AttendanceRepository attendances;
  final MemberRepository members;
  final CheckInAppController controller;
  DashboardHarness(this.attendances, this.members, this.controller);
}

/// 서버 객체만 만들고 `start()` 는 부르지 않는다. 대시보드는 컨트롤러의 두 notifier 만 읽으므로
/// 실제 소켓과 회전 타이머 없이 화면을 검증할 수 있다.
CheckInAppController _unstartedController(Database db) {
  final members = MemberRepository(db);
  final qr = QrTokenService();
  final logs = NotificationLogRepository(db);
  final server = CheckInServer(
    memberRepository: members,
    deviceBindingRepository: DeviceBindingRepository(db),
    attendanceService: AttendanceService(
      memberRepository: members,
      classRepository: ClassRepository(db),
      attendanceRepository: AttendanceRepository(db),
    ),
    qrTokenService: qr,
    verificationSessionService: VerificationSessionService(),
    notificationService: NotificationService(
      memberRepository: members,
      notifier: RecordingParentNotifier(logs),
    ),
    bindAttemptThrottle: BindAttemptThrottle(),
  );
  return CheckInAppController(
    qrTokenService: qr,
    server: server,
    networkInfo: NetworkInfo(),
  );
}

Future<DashboardHarness> pumpDashboard(
  WidgetTester tester, {
  Future<void> Function(DashboardHarness h)? seed,
  Duration refreshInterval = _quietInterval,
  DateTime? now,
  String? checkIn = _checkInUrl,
  String? checkOut = _checkOutUrl,
  bool waitForLoad = true,
  Duration bannerDuration = const Duration(seconds: 5),
}) async {
  final clockNow = now ?? kNow;
  final db = (await tester.runAsync(openTestDatabase))!;
  addTearDown(() => db.close());
  final controller = _unstartedController(db);
  addTearDown(controller.dispose);
  controller.checkInUrl.value = checkIn;
  controller.checkOutUrl.value = checkOut;
  final h = DashboardHarness(
    AttendanceRepository(db),
    MemberRepository(db),
    controller,
  );
  if (seed != null) await tester.runAsync(() => seed(h));
  await tester.pumpWidget(
    MaterialApp(
      home: DashboardScreen(
        controller: controller,
        attendanceRepository: h.attendances,
        memberRepository: h.members,
        refreshInterval: refreshInterval,
        clock: () => clockNow,
        bannerDuration: bannerDuration,
      ),
    ),
  );
  if (waitForLoad) {
    await pumpUntil(
      tester,
      () => absent(find.byType(CircularProgressIndicator)),
    );
  }
  return h;
}

/// 등원 카드 또는 하원 카드 안의 QR 위젯.
Finder qrIn(String cardKey) => find.descendant(
  of: find.byKey(Key(cardKey)),
  matching: find.byType(QrImageView),
);

/// qr_flutter 는 QR 의 data 를 private 으로 두어 테스트에서 읽을 수 없다. 대신 카드가 들고
/// 있는 주소를 본다 — 카드는 그 값을 그대로 `QrImageView(data:)` 에 넘긴다.
String? cardUrl(WidgetTester tester, String cardKey) =>
    tester.widget<QrCard>(find.byKey(Key(cardKey))).url;

// ── 날짜·기록 헬퍼 ──────────────────────────────────────────────────────────

/// [day] 의 [h]:[m] 을 저장 형식(ISO8601)으로 만든다.
String atOn(DateTime day, int h, int m) =>
    DateTime(day.year, day.month, day.day, h, m).toIso8601String();

/// [day] 날짜 행을 하나 넣는다. 등원일의 행이 곧 그 방문의 행이다.
Future<void> recordOn(
  DashboardHarness h,
  int memberId,
  DateTime day, {
  String? checkIn,
  String? checkOut,
  AttendanceStatus status = AttendanceStatus.present,
}) => h.attendances.insert(
  Attendance(
    memberId: memberId,
    date: AttendanceService.formatDate(day),
    checkInTime: checkIn,
    checkOutTime: checkOut,
    status: status,
  ),
);

/// 요약 줄이 그려질 때까지 기다린다. 요약은 첫 로드가 끝난 뒤에만 그려진다.
Future<void> waitForSummary(WidgetTester tester, String summary) =>
    pumpUntil(tester, () => shown(find.text(summary)));

void main() {
  group('체크 완료 배너', () {
    testWidgets('등원 이벤트가 오면 이름과 완료 문구를 띄우고 시간이 지나면 사라진다', (tester) async {
      final h = await pumpDashboard(
        tester,
        bannerDuration: const Duration(seconds: 3),
      );
      expect(find.byKey(const Key('checkInBanner')), findsNothing);

      h.controller.server.checkInEventBus.publish(
        const CheckInEvent(memberName: '홍길동', kind: QrKind.checkIn),
      );
      await tester.pump();
      expect(find.text('홍길동 님 등원 완료'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('checkInBanner')), findsNothing);
    });

    testWidgets('지각과 하원은 문구가 다르다', (tester) async {
      final h = await pumpDashboard(tester);
      final bus = h.controller.server.checkInEventBus;

      // 이벤트는 배너와 함께 목록 재조회를 일으킨다. 맨 pump() 로는 그 DB 조회가 끝나지
      // 않아 sqflite 가 만든 잠금 타이머가 남고 테스트가 pending timer 로 실패한다.
      bus.publish(
        const CheckInEvent(
          memberName: '김지각',
          kind: QrKind.checkIn,
          isLate: true,
        ),
      );
      await pumpUntil(tester, () => shown(find.text('김지각 님 등원 완료 (지각)')));
      expect(find.text('김지각 님 등원 완료 (지각)'), findsOneWidget);

      bus.publish(const CheckInEvent(memberName: '이하원', kind: QrKind.checkOut));
      await pumpUntil(tester, () => shown(find.text('이하원 님 하원 완료')));
      expect(find.text('이하원 님 하원 완료'), findsOneWidget);
      expect(find.textContaining('김지각'), findsNothing);

      // 남은 배너 타이머를 정리한다.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('정정 A — QR 을 라벨과 함께 그린다', () {
    testWidgets('등원 카드와 하원 카드가 각각 QR 을 갖고, 라벨이 같은 카드 안에 있다', (tester) async {
      await pumpDashboard(tester);

      expect(find.byType(QrImageView), findsNWidgets(2));
      expect(qrIn('checkInCard'), findsOneWidget);
      expect(qrIn('checkOutCard'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('checkInCard')),
          matching: find.text('등원'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('checkOutCard')),
          matching: find.text('하원'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('각 QR 카드가 받은 주소는 해당 notifier 값과 같고, 두 값은 서로 다르다', (
      tester,
    ) async {
      await pumpDashboard(tester);

      final inUrl = cardUrl(tester, 'checkInCard');
      final outUrl = cardUrl(tester, 'checkOutCard');
      expect(inUrl, _checkInUrl);
      expect(outUrl, _checkOutUrl);
      expect(inUrl, isNot(outUrl));
    });

    testWidgets('URL 이 아직 null 이면 그 카드에는 로딩 표시가 보이고 QR 은 없다', (tester) async {
      await pumpDashboard(tester, checkIn: null, waitForLoad: false);
      await pumpUntil(tester, () => shown(qrIn('checkOutCard')));

      expect(qrIn('checkInCard'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('checkInCard')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    });

    testWidgets('notifier 값이 바뀌면 QR 카드의 주소도 따라 바뀐다', (tester) async {
      final h = await pumpDashboard(tester);

      h.controller.checkInUrl.value =
          'http://192.168.0.10:8080/checkin?token=NEW';
      await tester.pump();

      expect(
        cardUrl(tester, 'checkInCard'),
        'http://192.168.0.10:8080/checkin?token=NEW',
      );
    });
  });

  group('정정 B — 오늘 현황을 등원·하원·체류·미하원으로 보여준다', () {
    testWidgets('등원 후 1시간이면 체류 중이고 미하원이 아니다', (tester) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          await recordOn(h, id, kToday, checkIn: atOn(kToday, 11, 0));
        },
      );
      await waitForSummary(tester, '등원 1 · 하원 0 · 체류 중 1 · 미하원 0');

      expect(inRow(find.text('등원 11:00')), findsOneWidget);
      expect(inRow(find.text('체류 중')), findsOneWidget);
      expect(inRow(find.text('미하원')), findsNothing);
    });

    testWidgets('등원 후 13시간이면 미하원이고 체류 중이 아니다', (tester) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          // 현재 12:00 기준 13시간 전은 어제 23:00.
          await recordOn(h, id, kYesterday, checkIn: atOn(kYesterday, 23, 0));
        },
      );
      // 요약은 오늘 행만 센다. 어제 행은 이전 날짜 구역에 있다.
      await waitForSummary(tester, '등원 0 · 하원 0 · 체류 중 0 · 미하원 0');

      expect(inRow(find.text('미하원')), findsOneWidget);
      expect(inRow(find.text('체류 중')), findsNothing);
      expect(inRow(find.text('2026-10-16')), findsOneWidget);
      expect(find.text(previousSectionTitle), findsOneWidget);
    });

    testWidgets('등원과 하원을 모두 한 회원은 하원 시각이 보이고 체류·미하원 어디에도 들지 않는다', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          await recordOn(
            h,
            id,
            kToday,
            checkIn: atOn(kToday, 9, 5),
            checkOut: atOn(kToday, 10, 30),
          );
        },
      );
      await waitForSummary(tester, '등원 1 · 하원 1 · 체류 중 0 · 미하원 0');

      expect(inRow(find.text('하원 10:30')), findsOneWidget);
      expect(inRow(find.text('체류 중')), findsNothing);
      expect(inRow(find.text('미하원')), findsNothing);
    });

    testWidgets('자동 결석 행은 등원 수에도 체류·미하원에도 들지 않는다', (tester) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final present = await h.members.insert(const Member(name: '홍길동'));
          await recordOn(h, present, kToday, checkIn: atOn(kToday, 11, 0));
          final absent = await h.members.insert(const Member(name: '이영희'));
          await recordOn(h, absent, kToday, status: AttendanceStatus.absent);
        },
      );
      await waitForSummary(tester, '등원 1 · 하원 0 · 체류 중 1 · 미하원 0');

      expect(inRow(find.text('등원 기록 없음')), findsOneWidget);
    });

    testWidgets('어제 23:50 에 등원해 아직 안 나간 사람은 00:30 에도 체류 중으로 보이고 날짜가 함께 보인다', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        now: DateTime(2026, 10, 17, 0, 30),
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          await recordOn(h, id, kYesterday, checkIn: atOn(kYesterday, 23, 50));
        },
      );
      // 요약은 오늘 행 기준이라 0 이다. 체류자는 이전 날짜 구역에 날짜와 함께 보인다.
      await waitForSummary(tester, '등원 0 · 하원 0 · 체류 중 0 · 미하원 0');

      expect(inRow(find.text('홍길동')), findsOneWidget);
      expect(inRow(find.text('2026-10-16')), findsOneWidget);
      expect(inRow(find.text('등원 23:50')), findsOneWidget);
      expect(inRow(find.text('체류 중')), findsOneWidget);
    });

    testWidgets('자정을 넘겨 하원한 방문은 하원 순간에도 목록에 남고 하원 시각과 날짜가 보인다', (tester) async {
      // 어제 23:50 등원, 오늘 00:20 하원. 지금은 09:00 이므로 창 안이다.
      await pumpDashboard(
        tester,
        now: DateTime(2026, 10, 17, 9, 0),
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          await recordOn(
            h,
            id,
            kYesterday,
            checkIn: atOn(kYesterday, 23, 50),
            checkOut: atOn(kToday, 0, 20),
          );
        },
      );
      await waitForSummary(tester, '등원 0 · 하원 0 · 체류 중 0 · 미하원 0');

      expect(inRow(find.text('홍길동')), findsOneWidget);
      expect(inRow(find.text('2026-10-16')), findsOneWidget);
      expect(inRow(find.text('등원 23:50')), findsOneWidget);
      expect(inRow(find.text('하원 00:20')), findsOneWidget);
      expect(find.text(previousSectionTitle), findsOneWidget);
    });

    testWidgets('창을 넘긴 과거 닫힌 세션은 목록에 들어오지 않는다', (tester) async {
      // 지금 12:00. 어제 09:00~10:00 방문은 등원 후 27시간이 지나 창 밖이다.
      await pumpDashboard(
        tester,
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          await recordOn(
            h,
            id,
            kYesterday,
            checkIn: atOn(kYesterday, 9, 0),
            checkOut: atOn(kYesterday, 10, 0),
          );
        },
      );
      await waitForSummary(tester, '등원 0 · 하원 0 · 체류 중 0 · 미하원 0');

      expect(find.byType(ListTile), findsNothing);
      expect(find.text(previousSectionTitle), findsNothing);
    });

    testWidgets('요약은 오늘 행만 세고, 같은 시각의 과거 체류자는 요약에 섞지 않는다', (tester) async {
      // 지금 00:30. 오늘 00:10 등원(체류 중)과 어제 23:50 등원(체류 중)이 함께 있다.
      await pumpDashboard(
        tester,
        now: DateTime(2026, 10, 17, 0, 30),
        seed: (h) async {
          final today = await h.members.insert(const Member(name: '오늘등원'));
          await recordOn(h, today, kToday, checkIn: atOn(kToday, 0, 10));
          final past = await h.members.insert(const Member(name: '어제등원'));
          await recordOn(
            h,
            past,
            kYesterday,
            checkIn: atOn(kYesterday, 23, 50),
          );
        },
      );
      await waitForSummary(tester, '등원 1 · 하원 0 · 체류 중 1 · 미하원 0');

      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text(previousSectionTitle), findsOneWidget);
      expect(inRow(find.text('2026-10-16')), findsOneWidget);
      expect(inRow(find.text('2026-10-17')), findsNothing);
    });

    testWidgets('오늘 행이면서 체류 중인 행은 목록에 한 번만 나온다', (tester) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          await recordOn(h, id, kToday, checkIn: atOn(kToday, 11, 0));
        },
      );
      await waitForSummary(tester, '등원 1 · 하원 0 · 체류 중 1 · 미하원 0');

      expect(find.byType(ListTile), findsOneWidget);
    });
  });

  group('정정 C — 상태는 한글 라벨로 보인다', () {
    testWidgets('출석·지각·결석이 영문 enum 이름이 아니라 한글로 보인다', (tester) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final a = await h.members.insert(const Member(name: '홍길동'));
          await recordOn(h, a, kToday, checkIn: atOn(kToday, 9, 5));
          final b = await h.members.insert(const Member(name: '김지각'));
          await recordOn(
            h,
            b,
            kToday,
            checkIn: atOn(kToday, 9, 30),
            status: AttendanceStatus.late,
          );
          final c = await h.members.insert(const Member(name: '이영희'));
          await recordOn(h, c, kToday, status: AttendanceStatus.absent);
        },
      );
      await waitForSummary(tester, '등원 2 · 하원 0 · 체류 중 2 · 미하원 0');

      expect(inRow(find.text('출석')), findsOneWidget);
      expect(inRow(find.text('지각')), findsOneWidget);
      expect(inRow(find.text('결석')), findsOneWidget);
      expect(find.text('present'), findsNothing);
      expect(find.text('late'), findsNothing);
      expect(find.text('absent'), findsNothing);
    });
  });

  group('정정 E — 새로고침 타이머는 주입되고 dispose 에서 취소된다', () {
    testWidgets('첫 로드 전에는 로딩 표시만 보이고 요약은 보이지 않는다', (tester) async {
      await pumpDashboard(tester, waitForLoad: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('등원 0 · 하원 0 · 체류 중 0 · 미하원 0'), findsNothing);

      await waitForSummary(tester, '등원 0 · 하원 0 · 체류 중 0 · 미하원 0');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('새로고침 간격이 지나면 그 사이 DB 에 생긴 행이 목록에 나타난다', (tester) async {
      final h = await pumpDashboard(
        tester,
        refreshInterval: const Duration(milliseconds: 50),
      );
      await waitForSummary(tester, '등원 0 · 하원 0 · 체류 중 0 · 미하원 0');

      await tester.runAsync(() async {
        final id = await h.members.insert(const Member(name: '홍길동'));
        await recordOn(h, id, kToday, checkIn: atOn(kToday, 11, 0));
      });

      await pumpUntil(tester, () => shown(inRow(find.text('홍길동'))));
      expect(inRow(find.text('등원 11:00')), findsOneWidget);
      expect(find.text('등원 1 · 하원 0 · 체류 중 1 · 미하원 0'), findsOneWidget);
    });

    testWidgets('화면을 내리면 새로고침 타이머도 취소된다', (tester) async {
      await pumpDashboard(
        tester,
        refreshInterval: const Duration(milliseconds: 50),
      );
      await waitForSummary(tester, '등원 0 · 하원 0 · 체류 중 0 · 미하원 0');

      // 타이머가 남아 있으면 테스트 종료 시 "pending timer" 로 실패한다.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
