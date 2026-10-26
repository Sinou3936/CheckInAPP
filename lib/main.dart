import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:checkin_app/db/database_helper.dart';
import 'package:checkin_app/repositories/app_state_repository.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/absence_scheduler.dart';
import 'package:checkin_app/services/admin_bind_code_service.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/bind_attempt_throttle.dart';
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/notification_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/services/verification_session_service.dart';
import 'package:checkin_app/ui/screens/attendance_history_screen.dart';
import 'package:checkin_app/ui/screens/audit_log_screen.dart';
import 'package:checkin_app/ui/screens/class_management_screen.dart';
import 'package:checkin_app/ui/screens/dashboard_screen.dart';
import 'package:checkin_app/ui/screens/member_management_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 데스크톱은 sqflite 가 아니라 sqflite_common_ffi 를 쓴다.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final supportDir = await getApplicationSupportDirectory();
  final dbPath = p.join(supportDir.path, 'checkin_app.db');

  runApp(CheckInApp(dbPath: dbPath));
}

class CheckInApp extends StatefulWidget {
  /// null 이면 인메모리 DB 를 쓴다 (위젯/스모크 테스트용).
  final String? dbPath;

  /// 내장 체크인 서버의 포트. 테스트는 0(임의 포트)을 넘겨 실제 8080 과 다투지 않게 한다.
  final int serverPort;

  const CheckInApp({super.key, required this.dbPath, this.serverPort = 8080});

  @override
  State<CheckInApp> createState() => _CheckInAppState();
}

class _CheckInAppState extends State<CheckInApp> {
  MemberRepository? _memberRepository;
  ClassRepository? _classRepository;
  AttendanceRepository? _attendanceRepository;
  DeviceBindingRepository? _deviceBindingRepository;
  NotificationLogRepository? _notificationLogRepository;
  CheckInAppController? _controller;
  AbsenceScheduler? _absenceScheduler;
  AdminBindCodeService? _adminBindCodeService;
  bool _disposed = false;

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
    final notificationLogRepository = NotificationLogRepository(db);
    final attendanceService = AttendanceService(
      memberRepository: memberRepository,
      classRepository: classRepository,
      attendanceRepository: attendanceRepository,
    );
    // 서버와 컨트롤러는 반드시 같은 QrTokenService 를 공유해야 한다. 따로 만들면
    // 화면에 뜬 QR 토큰을 서버가 모르는 토큰으로 판정한다.
    final qrTokenService = QrTokenService();
    // 서버와 회원 화면이 같은 인스턴스를 공유해야 화면에서 발급한 코드를 서버가 알아본다.
    final adminBindCodeService = AdminBindCodeService();
    final server = CheckInServer(
      memberRepository: memberRepository,
      deviceBindingRepository: deviceBindingRepository,
      attendanceService: attendanceService,
      qrTokenService: qrTokenService,
      verificationSessionService: VerificationSessionService(),
      notificationService: NotificationService(
        memberRepository: memberRepository,
        notifier: RecordingParentNotifier(notificationLogRepository),
      ),
      bindAttemptThrottle: BindAttemptThrottle(),
      adminBindCodeService: adminBindCodeService,
    );
    final controller = CheckInAppController(
      qrTokenService: qrTokenService,
      server: server,
      networkInfo: NetworkInfo(),
      port: widget.serverPort,
    );
    _controller = controller;
    await controller.start();

    final absenceScheduler = AbsenceScheduler(
      attendanceService: attendanceService,
      appStateRepository: AppStateRepository(db),
    );
    absenceScheduler.start();
    _absenceScheduler = absenceScheduler;

    if (!mounted) return;
    setState(() {
      _memberRepository = memberRepository;
      _classRepository = classRepository;
      _attendanceRepository = attendanceRepository;
      _adminBindCodeService = adminBindCodeService;
      _deviceBindingRepository = deviceBindingRepository;
      _notificationLogRepository = notificationLogRepository;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _absenceScheduler?.stop();
    final controller = _controller;
    // 서버를 내린다. 타이머는 stop() 안에서 동기적으로 끊기고, 소켓은 await 뒤에 닫힌다.
    controller?.stop().whenComplete(controller.dispose);
    // **DB 는 닫지 않는다.** 타이머를 끊어도 이미 떠난 비동기 조회는 취소할 수 없어서, 여기서
    // 닫으면 그것들이 닫힌 핸들을 만져 처리되지 않은 예외가 된다 (대시보드의 _refresh,
    // 결석 스케줄러의 app_state 쓰기가 실제로 그랬다). 핸들의 수명은 프로세스 수명이고
    // 프로세스가 끝나면 OS 가 정리하므로 닫아서 얻는 것이 없다.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memberRepository = _memberRepository;
    final classRepository = _classRepository;
    final attendanceRepository = _attendanceRepository;
    final deviceBindingRepository = _deviceBindingRepository;
    final notificationLogRepository = _notificationLogRepository;
    final adminBindCodeService = _adminBindCodeService;
    final controller = _controller;

    if (_disposed ||
        memberRepository == null ||
        classRepository == null ||
        attendanceRepository == null ||
        deviceBindingRepository == null ||
        notificationLogRepository == null ||
        adminBindCodeService == null ||
        controller == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      title: 'CheckInApp',
      home: _HomeShell(
        controller: controller,
        memberRepository: memberRepository,
        classRepository: classRepository,
        attendanceRepository: attendanceRepository,
        deviceBindingRepository: deviceBindingRepository,
        notificationLogRepository: notificationLogRepository,
        adminBindCodeService: adminBindCodeService,
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  final CheckInAppController controller;
  final MemberRepository memberRepository;
  final ClassRepository classRepository;
  final AttendanceRepository attendanceRepository;
  final DeviceBindingRepository deviceBindingRepository;
  final NotificationLogRepository notificationLogRepository;
  final AdminBindCodeService adminBindCodeService;

  const _HomeShell({
    required this.controller,
    required this.memberRepository,
    required this.classRepository,
    required this.attendanceRepository,
    required this.deviceBindingRepository,
    required this.notificationLogRepository,
    required this.adminBindCodeService,
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
        adminBindCodeService: widget.adminBindCodeService,
      ),
      ClassManagementScreen(classRepository: widget.classRepository),
      AttendanceHistoryScreen(
        memberRepository: widget.memberRepository,
        attendanceRepository: widget.attendanceRepository,
      ),
      AuditLogScreen(
        deviceBindingRepository: widget.deviceBindingRepository,
        notificationLogRepository: widget.notificationLogRepository,
        memberRepository: widget.memberRepository,
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
          NavigationDestination(icon: Icon(Icons.fact_check), label: '점검'),
        ],
      ),
    );
  }
}
