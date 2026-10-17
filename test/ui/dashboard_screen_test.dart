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
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/notification_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/services/verification_session_service.dart';
import 'package:checkin_app/ui/screens/dashboard_screen.dart';

import '../helpers/test_db.dart';
import '../helpers/widget_test_helpers.dart';

const _checkInUrl = 'http://192.168.0.10:8080/checkin?token=IN-TOKEN';
const _checkOutUrl = 'http://192.168.0.10:8080/checkin?token=OUT-TOKEN';

/// 테스트 중에 새로고침 타이머가 끼어들지 않도록 충분히 긴 간격을 쓴다.
const _quietInterval = Duration(hours: 1);

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
  String? checkIn = _checkInUrl,
  String? checkOut = _checkOutUrl,
  bool waitForLoad = true,
}) async {
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

/// 대시보드는 `DateTime.now()` 의 날짜 행을 읽는다. 테스트도 같은 기준으로 행을 만든다.
String todayKey() => AttendanceService.formatDate(DateTime.now());

/// 오늘(+[dayOffset]일)의 [hour]:[minute] 를 저장 형식(ISO8601)으로 만든다.
String at(int hour, int minute, {int dayOffset = 0}) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day + dayOffset,
    hour,
    minute,
  ).toIso8601String();
}

/// 오늘 날짜 행을 하나 넣는다. 등원일의 행이 곧 그 방문의 행이다.
Future<void> recordToday(
  DashboardHarness h,
  int memberId, {
  String? checkIn,
  String? checkOut,
  AttendanceStatus status = AttendanceStatus.present,
}) => h.attendances.insert(
  Attendance(
    memberId: memberId,
    date: todayKey(),
    checkInTime: checkIn,
    checkOutTime: checkOut,
    status: status,
  ),
);

/// 요약 줄이 그려질 때까지 기다린다. 요약은 첫 로드가 끝난 뒤에만 그려진다.
Future<void> waitForSummary(WidgetTester tester, String summary) =>
    pumpUntil(tester, () => shown(find.text(summary)));

void main() {
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

  group('정정 B — 오늘 현황을 등원·하원·미하원으로 보여준다', () {
    testWidgets('등원만 한 회원은 미하원으로 보이고 미하원 수에 든다', (tester) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          await recordToday(h, id, checkIn: at(9, 5));
        },
      );
      await waitForSummary(tester, '등원 1 · 하원 0 · 미하원 1');

      expect(inRow(find.text('홍길동')), findsOneWidget);
      expect(inRow(find.text('등원 09:05')), findsOneWidget);
      expect(inRow(find.text('미하원')), findsOneWidget);
    });

    testWidgets('등원과 하원을 모두 한 회원은 하원 시각이 보이고 미하원 수에 들지 않는다', (tester) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          await recordToday(h, id, checkIn: at(9, 5), checkOut: at(10, 30));
        },
      );
      await waitForSummary(tester, '등원 1 · 하원 1 · 미하원 0');

      expect(inRow(find.text('하원 10:30')), findsOneWidget);
      expect(inRow(find.text('미하원')), findsNothing);
    });

    testWidgets('자동 결석 행은 등원 수에 들지 않는다', (tester) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final present = await h.members.insert(const Member(name: '홍길동'));
          await recordToday(h, present, checkIn: at(9, 5));
          final absent = await h.members.insert(const Member(name: '이영희'));
          await recordToday(h, absent, status: AttendanceStatus.absent);
        },
      );
      await waitForSummary(tester, '등원 1 · 하원 0 · 미하원 1');

      expect(inRow(find.text('이영희')), findsOneWidget);
      expect(inRow(find.text('등원 기록 없음')), findsOneWidget);
    });

    testWidgets('자정을 넘겨 하원해도 등원한 날 행의 하원으로 보이고 미하원이 아니다', (tester) async {
      // 등원은 오늘 23:50, 하원은 내일 00:20. 행의 date 는 등원한 날(오늘)이다.
      await pumpDashboard(
        tester,
        seed: (h) async {
          final id = await h.members.insert(const Member(name: '홍길동'));
          await recordToday(
            h,
            id,
            checkIn: at(23, 50),
            checkOut: at(0, 20, dayOffset: 1),
          );
        },
      );
      await waitForSummary(tester, '등원 1 · 하원 1 · 미하원 0');

      expect(inRow(find.text('등원 23:50')), findsOneWidget);
      expect(inRow(find.text('하원 00:20')), findsOneWidget);
      expect(inRow(find.text('미하원')), findsNothing);
    });
  });

  group('정정 C — 상태는 한글 라벨로 보인다', () {
    testWidgets('출석·지각·결석이 영문 enum 이름이 아니라 한글로 보인다', (tester) async {
      await pumpDashboard(
        tester,
        seed: (h) async {
          final a = await h.members.insert(const Member(name: '홍길동'));
          await recordToday(h, a, checkIn: at(9, 5));
          final b = await h.members.insert(const Member(name: '김지각'));
          await recordToday(
            h,
            b,
            checkIn: at(9, 30),
            status: AttendanceStatus.late,
          );
          final c = await h.members.insert(const Member(name: '이영희'));
          await recordToday(h, c, status: AttendanceStatus.absent);
        },
      );
      await waitForSummary(tester, '등원 2 · 하원 0 · 미하원 2');

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
      expect(find.text('등원 0 · 하원 0 · 미하원 0'), findsNothing);

      await waitForSummary(tester, '등원 0 · 하원 0 · 미하원 0');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('새로고침 간격이 지나면 그 사이 DB 에 생긴 행이 목록에 나타난다', (tester) async {
      final h = await pumpDashboard(
        tester,
        refreshInterval: const Duration(milliseconds: 50),
      );
      await waitForSummary(tester, '등원 0 · 하원 0 · 미하원 0');

      await tester.runAsync(() async {
        final id = await h.members.insert(const Member(name: '홍길동'));
        await recordToday(h, id, checkIn: at(9, 5));
      });

      await pumpUntil(tester, () => shown(inRow(find.text('홍길동'))));
      expect(inRow(find.text('등원 09:05')), findsOneWidget);
      expect(find.text('등원 1 · 하원 0 · 미하원 1'), findsOneWidget);
    });

    testWidgets('화면을 내리면 새로고침 타이머도 취소된다', (tester) async {
      await pumpDashboard(
        tester,
        refreshInterval: const Duration(milliseconds: 50),
      );
      await waitForSummary(tester, '등원 0 · 하원 0 · 미하원 0');

      // 타이머가 남아 있으면 테스트 종료 시 "pending timer" 로 실패한다.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
